


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "private"."normalize_text"("input_text" "text") RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $$
  select trim(
    regexp_replace(
      lower(extensions.unaccent(coalesce(input_text, ''))),
      '[^a-z0-9]+',
      ' ',
      'g'
    )
  );
$$;


ALTER FUNCTION "private"."normalize_text"("input_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."prepare_experience"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $$
declare
  normalized_value text;
begin
  normalized_value := private.normalize_text(new.title);
  new.normalized_title := normalized_value;

  new.dedupe_key :=
    encode(
      digest(
        concat_ws(
          '|',
          new.kind,
          normalized_value,
          coalesce(new.venue_id::text, ''),
          coalesce(new.organizer_id::text, '')
        ),
        'sha256'
      ),
      'hex'
    );

  if new.publication_status = 'published'
     and new.published_at is null then
    new.published_at := now();
  end if;

  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "private"."prepare_experience"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."prepare_organizer"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $$
begin
  new.normalized_name := private.normalize_text(new.name);
  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "private"."prepare_organizer"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."prepare_venue"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $$
begin
  new.normalized_name := private.normalize_text(new.name);

  if new.latitude is not null and new.longitude is not null then
    new.location :=
      extensions.st_setsrid(
        extensions.st_makepoint(new.longitude, new.latitude),
        4326
      )::extensions.geography;
  else
    new.location := null;
  end if;

  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "private"."prepare_venue"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "private"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."validate_offer_occurrence"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $$
declare
  occurrence_experience uuid;
begin
  if new.occurrence_id is null then
    return new;
  end if;

  select experience_id
    into occurrence_experience
  from public.experience_occurrences
  where id = new.occurrence_id;

  if occurrence_experience is distinct from new.experience_id then
    raise exception
      'Occurrence % does not belong to experience %',
      new.occurrence_id,
      new.experience_id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "private"."validate_offer_occurrence"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."catalog_private_bridge"("p_action" "text", "p_payload" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_result jsonb;
  v_id uuid;
  v_success boolean;
begin
  case p_action

    when 'get_connector' then
      select jsonb_build_object(
        'found', true,
        'id', c.id,
        'sourceId', c.source_id,
        'enabled', c.enabled
      )
      into v_result
      from private.source_connectors c
      where c.connector_key = p_payload->>'connectorKey'
      limit 1;

      return coalesce(v_result, jsonb_build_object('found', false));

    when 'start_run' then
      insert into private.ingestion_runs (
        connector_id,
        status,
        trigger_type,
        stats
      )
      values (
        (p_payload->>'connectorId')::uuid,
        'running',
        coalesce(nullif(p_payload->>'triggerType', ''), 'manual'),
        coalesce(p_payload->'stats', '{}'::jsonb)
      )
      returning id into v_id;

      return jsonb_build_object('id', v_id);

    when 'finish_run' then
      update private.ingestion_runs
      set
        status = coalesce(nullif(p_payload->>'status', ''), 'completed'),
        fetched_count = coalesce((p_payload->>'fetchedCount')::integer, 0),
        inserted_count = coalesce((p_payload->>'insertedCount')::integer, 0),
        updated_count = coalesce((p_payload->>'updatedCount')::integer, 0),
        skipped_count = coalesce((p_payload->>'skippedCount')::integer, 0),
        error_count = coalesce((p_payload->>'errorCount')::integer, 0),
        stats = coalesce(p_payload->'stats', '{}'::jsonb),
        error_summary = nullif(p_payload->>'errorSummary', ''),
        finished_at = now()
      where id = (p_payload->>'runId')::uuid;

      return jsonb_build_object('ok', true);

    when 'update_connector' then
      v_success := coalesce((p_payload->>'success')::boolean, false);

      if v_success then
        update private.source_connectors
        set
          enabled = true,
          last_success_at = now(),
          last_error_at = case
            when nullif(p_payload->>'errorMessage', '') is null then null
            else now()
          end,
          last_error_message = nullif(p_payload->>'errorMessage', ''),
          updated_at = now()
        where id = (p_payload->>'connectorId')::uuid;
      else
        update private.source_connectors
        set
          last_error_at = now(),
          last_error_message = nullif(p_payload->>'errorMessage', ''),
          updated_at = now()
        where id = (p_payload->>'connectorId')::uuid;
      end if;

      return jsonb_build_object('ok', true);

    when 'get_source_record' then
      select jsonb_build_object(
        'found', true,
        'id', r.id,
        'canonicalVenueId', r.canonical_venue_id,
        'canonicalExperienceId', r.canonical_experience_id,
        'canonicalOccurrenceId', r.canonical_occurrence_id,
        'canonicalOfferId', r.canonical_offer_id
      )
      into v_result
      from private.source_records r
      where r.source_id = (p_payload->>'sourceId')::uuid
        and r.entity_kind = p_payload->>'entityKind'
        and r.external_id = p_payload->>'externalId'
      limit 1;

      return coalesce(v_result, jsonb_build_object('found', false));

    when 'upsert_source_record' then
      insert into private.source_records (
        source_id,
        ingestion_run_id,
        entity_kind,
        external_id,
        source_url,
        payload_hash,
        raw_payload,
        parsed_payload,
        processing_status,
        canonical_venue_id,
        canonical_experience_id,
        canonical_occurrence_id,
        canonical_offer_id,
        last_seen_at,
        fetched_at,
        expires_at,
        deleted_at
      )
      values (
        (p_payload->>'sourceId')::uuid,
        nullif(p_payload->>'ingestionRunId', '')::uuid,
        p_payload->>'entityKind',
        p_payload->>'externalId',
        nullif(p_payload->>'sourceUrl', ''),
        nullif(p_payload->>'payloadHash', ''),
        coalesce(p_payload->'rawPayload', '{}'::jsonb),
        coalesce(p_payload->'parsedPayload', '{}'::jsonb),
        coalesce(nullif(p_payload->>'processingStatus', ''), 'pending'),
        nullif(p_payload->>'canonicalVenueId', '')::uuid,
        nullif(p_payload->>'canonicalExperienceId', '')::uuid,
        nullif(p_payload->>'canonicalOccurrenceId', '')::uuid,
        nullif(p_payload->>'canonicalOfferId', '')::uuid,
        coalesce(nullif(p_payload->>'lastSeenAt', '')::timestamptz, now()),
        coalesce(nullif(p_payload->>'fetchedAt', '')::timestamptz, now()),
        nullif(p_payload->>'expiresAt', '')::timestamptz,
        nullif(p_payload->>'deletedAt', '')::timestamptz
      )
      on conflict (source_id, entity_kind, external_id)
      do update set
        ingestion_run_id = excluded.ingestion_run_id,
        source_url = excluded.source_url,
        payload_hash = excluded.payload_hash,
        raw_payload = excluded.raw_payload,
        parsed_payload = excluded.parsed_payload,
        processing_status = excluded.processing_status,
        canonical_venue_id = excluded.canonical_venue_id,
        canonical_experience_id = excluded.canonical_experience_id,
        canonical_occurrence_id = excluded.canonical_occurrence_id,
        canonical_offer_id = excluded.canonical_offer_id,
        last_seen_at = excluded.last_seen_at,
        fetched_at = excluded.fetched_at,
        expires_at = excluded.expires_at,
        deleted_at = excluded.deleted_at,
        updated_at = now()
      returning id into v_id;

      return jsonb_build_object('id', v_id);

    else
      raise exception 'Unknown catalog_private_bridge action: %', p_action;
  end case;
end;
$$;


ALTER FUNCTION "public"."catalog_private_bridge"("p_action" "text", "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_experiences"("p_latitude" double precision, "p_longitude" double precision, "p_radius_km" double precision DEFAULT 50, "p_from" timestamp with time zone DEFAULT "now"(), "p_to" timestamp with time zone DEFAULT ("now"() + '90 days'::interval), "p_kinds" "text"[] DEFAULT NULL::"text"[], "p_category_codes" "text"[] DEFAULT NULL::"text"[], "p_min_child_age" smallint DEFAULT NULL::smallint, "p_max_child_age" smallint DEFAULT NULL::smallint, "p_free_only" boolean DEFAULT false, "p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0) RETURNS TABLE("id" "uuid", "kind" "text", "title" "text", "summary" "text", "hero_image_url" "text", "venue_name" "text", "city" "text", "region" "text", "country_code" "text", "latitude" double precision, "longitude" double precision, "distance_km" numeric, "primary_category_code" "text", "primary_category_name" "text", "primary_category_emoji" "text", "next_occurrence_id" "uuid", "next_starts_at" timestamp with time zone, "next_ends_at" timestamp with time zone, "next_all_day" boolean, "price_min" numeric, "price_max" numeric, "currency" character, "offer_name" "text", "purchase_url" "text", "free_entry" boolean, "family_score" smallint, "quality_score" smallint)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $$
  with origin as (
    select
      extensions.st_setsrid(
        extensions.st_makepoint(p_longitude, p_latitude),
        4326
      )::extensions.geography as point
  )
  select
    e.id,
    e.kind,
    e.title,
    e.summary,
    e.hero_image_url,

    v.name as venue_name,
    v.city,
    v.region,
    v.country_code,
    v.latitude,
    v.longitude,
    round(
      (
        extensions.st_distance(v.location, origin.point) / 1000.0
      )::numeric,
      1
    ) as distance_km,

    primary_category.code,
    primary_category.name_sk,
    primary_category.emoji,

    selected_occurrence.id,
    selected_occurrence.starts_at,
    selected_occurrence.ends_at,
    selected_occurrence.all_day,

    best_offer.price_min,
    best_offer.price_max,
    best_offer.currency,
    best_offer.offer_name,
    best_offer.purchase_url,

    e.free_entry,
    e.family_score,
    e.quality_score
  from public.experiences e
  join public.venues v
    on v.id = e.venue_id
  cross join origin
  left join lateral (
    select
      c.code,
      c.name_sk,
      c.emoji
    from public.experience_categories ec
    join public.categories c
      on c.code = ec.category_code
    where ec.experience_id = e.id
      and c.active = true
    order by ec.is_primary desc, c.sort_order asc
    limit 1
  ) primary_category on true
  left join lateral (
    select o.*
    from public.experience_occurrences o
    where o.experience_id = e.id
      and o.active = true
      and o.status in ('scheduled', 'rescheduled')
      and o.starts_at <= p_to
      and coalesce(o.ends_at, o.starts_at) >= p_from
    order by o.starts_at asc
    limit 1
  ) selected_occurrence on true
  left join lateral (
    select t.*
    from public.ticket_offers t
    where t.experience_id = e.id
      and t.active = true
      and t.availability not in ('sold_out', 'unavailable')
      and (
        t.valid_until is null
        or t.valid_until >= now()
      )
      and (
        t.occurrence_id is null
        or t.occurrence_id = selected_occurrence.id
      )
    order by
      t.is_official desc,
      t.confidence desc,
      t.price_min asc nulls last,
      t.checked_at desc
    limit 1
  ) best_offer on true
  where e.publication_status = 'published'
    and e.active = true
    and v.active = true
    and v.location is not null
    and extensions.st_dwithin(
      v.location,
      origin.point,
      greatest(1, least(p_radius_km, 500)) * 1000
    )
    and (
      p_kinds is null
      or e.kind = any(p_kinds)
    )
    and (
      p_category_codes is null
      or exists (
        select 1
        from public.experience_categories ec_filter
        where ec_filter.experience_id = e.id
          and ec_filter.category_code = any(p_category_codes)
      )
    )
    and (
      p_min_child_age is null
      or e.age_min is null
      or e.age_min <= p_min_child_age
    )
    and (
      p_max_child_age is null
      or e.age_max is null
      or e.age_max >= p_max_child_age
    )
    and (
      not p_free_only
      or e.free_entry = true
      or coalesce(best_offer.price_min, 1) = 0
    )
    and (
      e.kind = 'attraction'
      or selected_occurrence.id is not null
    )
  order by
    case
      when selected_occurrence.starts_at is not null
       and selected_occurrence.starts_at < now() + interval '48 hours'
      then 0
      else 1
    end,
    e.family_score desc,
    distance_km asc,
    selected_occurrence.starts_at asc nulls last
  limit greatest(1, least(p_limit, 100))
  offset greatest(0, p_offset);
$$;


ALTER FUNCTION "public"."search_experiences"("p_latitude" double precision, "p_longitude" double precision, "p_radius_km" double precision, "p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_kinds" "text"[], "p_category_codes" "text"[], "p_min_child_age" smallint, "p_max_child_age" smallint, "p_free_only" boolean, "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "private"."dedupe_candidates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "entity_kind" "text" NOT NULL,
    "left_source_record_id" "uuid" NOT NULL,
    "right_source_record_id" "uuid" NOT NULL,
    "similarity_score" numeric(5,4) NOT NULL,
    "reasons" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "decision" "text" DEFAULT 'pending'::"text" NOT NULL,
    "decided_at" timestamp with time zone,
    "decided_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "dedupe_candidates_check" CHECK (("left_source_record_id" <> "right_source_record_id")),
    CONSTRAINT "dedupe_candidates_decision_check" CHECK (("decision" = ANY (ARRAY['pending'::"text", 'merged'::"text", 'not_duplicate'::"text", 'needs_review'::"text"]))),
    CONSTRAINT "dedupe_candidates_entity_kind_check" CHECK (("entity_kind" = ANY (ARRAY['venue'::"text", 'experience'::"text"]))),
    CONSTRAINT "dedupe_candidates_similarity_score_check" CHECK ((("similarity_score" >= (0)::numeric) AND ("similarity_score" <= (1)::numeric)))
);


ALTER TABLE "private"."dedupe_candidates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."ingestion_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "connector_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'running'::"text" NOT NULL,
    "trigger_type" "text" DEFAULT 'manual'::"text" NOT NULL,
    "cursor_before" "text",
    "cursor_after" "text",
    "fetched_count" integer DEFAULT 0 NOT NULL,
    "inserted_count" integer DEFAULT 0 NOT NULL,
    "updated_count" integer DEFAULT 0 NOT NULL,
    "skipped_count" integer DEFAULT 0 NOT NULL,
    "error_count" integer DEFAULT 0 NOT NULL,
    "stats" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "error_summary" "text",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "finished_at" timestamp with time zone,
    CONSTRAINT "ingestion_runs_status_check" CHECK (("status" = ANY (ARRAY['running'::"text", 'completed'::"text", 'partial'::"text", 'failed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "ingestion_runs_trigger_type_check" CHECK (("trigger_type" = ANY (ARRAY['manual'::"text", 'cron'::"text", 'webhook'::"text", 'on_demand'::"text"])))
);


ALTER TABLE "private"."ingestion_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."place_candidates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "google_place_id" "text" NOT NULL,
    "source_query" "text",
    "source_country" "text",
    "source_latitude" double precision,
    "source_longitude" double precision,
    "search_radius_meters" integer,
    "name" "text",
    "primary_type" "text",
    "latitude" double precision,
    "longitude" double precision,
    "raw_data" "jsonb" NOT NULL,
    "review_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "rejection_reason" "text",
    "discovered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "place_candidates_review_status_check" CHECK (("review_status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "private"."place_candidates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."quality_issues" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "entity_kind" "text" NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "severity" "text" NOT NULL,
    "issue_code" "text" NOT NULL,
    "details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "resolved" boolean DEFAULT false NOT NULL,
    "resolved_at" timestamp with time zone,
    "resolved_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "quality_issues_entity_kind_check" CHECK (("entity_kind" = ANY (ARRAY['venue'::"text", 'experience'::"text", 'occurrence'::"text", 'offer'::"text", 'media'::"text", 'source_record'::"text"]))),
    CONSTRAINT "quality_issues_severity_check" CHECK (("severity" = ANY (ARRAY['info'::"text", 'warning'::"text", 'error'::"text", 'critical'::"text"])))
);


ALTER TABLE "private"."quality_issues" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."schema_versions" (
    "version" "text" NOT NULL,
    "description" "text" NOT NULL,
    "applied_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "private"."schema_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."source_connectors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "source_id" "uuid" NOT NULL,
    "connector_key" "text" NOT NULL,
    "connector_mode" "text" NOT NULL,
    "endpoint_base_url" "text",
    "enabled" boolean DEFAULT false NOT NULL,
    "schedule_cron" "text",
    "country_codes" "text"[] DEFAULT ARRAY['SK'::"text", 'CZ'::"text"] NOT NULL,
    "config" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "secret_names" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "rate_limit_per_minute" integer,
    "cache_ttl_seconds" integer DEFAULT 86400 NOT NULL,
    "retention_days" integer DEFAULT 90 NOT NULL,
    "last_cursor" "text",
    "last_success_at" timestamp with time zone,
    "last_error_at" timestamp with time zone,
    "last_error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "source_connectors_cache_ttl_seconds_check" CHECK (("cache_ttl_seconds" >= 0)),
    CONSTRAINT "source_connectors_connector_mode_check" CHECK (("connector_mode" = ANY (ARRAY['api'::"text", 'feed'::"text", 'jsonld'::"text", 'html'::"text", 'pdf'::"text", 'search'::"text", 'manual'::"text", 'partner'::"text"]))),
    CONSTRAINT "source_connectors_rate_limit_per_minute_check" CHECK ((("rate_limit_per_minute" IS NULL) OR ("rate_limit_per_minute" > 0))),
    CONSTRAINT "source_connectors_retention_days_check" CHECK (("retention_days" >= 0))
);


ALTER TABLE "private"."source_connectors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."source_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "source_id" "uuid" NOT NULL,
    "ingestion_run_id" "uuid",
    "entity_kind" "text" NOT NULL,
    "external_id" "text" NOT NULL,
    "source_url" "text",
    "http_etag" "text",
    "http_last_modified" "text",
    "payload_hash" "text",
    "raw_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "parsed_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "processing_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "parse_error" "text",
    "canonical_venue_id" "uuid",
    "canonical_experience_id" "uuid",
    "canonical_occurrence_id" "uuid",
    "canonical_offer_id" "uuid",
    "first_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fetched_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "source_records_entity_kind_check" CHECK (("entity_kind" = ANY (ARRAY['venue'::"text", 'experience'::"text", 'occurrence'::"text", 'offer'::"text", 'media'::"text"]))),
    CONSTRAINT "source_records_processing_status_check" CHECK (("processing_status" = ANY (ARRAY['pending'::"text", 'parsed'::"text", 'matched'::"text", 'published'::"text", 'ignored'::"text", 'failed'::"text"])))
);


ALTER TABLE "private"."source_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."sync_runs" (
    "id" bigint NOT NULL,
    "job_name" "text" NOT NULL,
    "status" "text" NOT NULL,
    "places_found" integer DEFAULT 0 NOT NULL,
    "places_created" integer DEFAULT 0 NOT NULL,
    "places_updated" integer DEFAULT 0 NOT NULL,
    "error_message" "text",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "finished_at" timestamp with time zone,
    CONSTRAINT "sync_runs_status_check" CHECK (("status" = ANY (ARRAY['running'::"text", 'completed'::"text", 'failed'::"text"])))
);


ALTER TABLE "private"."sync_runs" OWNER TO "postgres";


ALTER TABLE "private"."sync_runs" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."sync_runs_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "private"."ticket_offer_snapshots" (
    "id" bigint NOT NULL,
    "ticket_offer_id" "uuid" NOT NULL,
    "price_min" numeric(12,2),
    "price_max" numeric(12,2),
    "currency" character(3),
    "availability" "text",
    "raw_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "captured_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "private"."ticket_offer_snapshots" OWNER TO "postgres";


ALTER TABLE "private"."ticket_offer_snapshots" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."ticket_offer_snapshots_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."categories" (
    "code" "text" NOT NULL,
    "name_sk" "text" NOT NULL,
    "name_cs" "text",
    "emoji" "text",
    "parent_code" "text",
    "family_relevance" smallint DEFAULT 50 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 100 NOT NULL,
    CONSTRAINT "categories_family_relevance_check" CHECK ((("family_relevance" >= 0) AND ("family_relevance" <= 100)))
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "external_id" "text",
    "source_name" "text" NOT NULL,
    "source_url" "text",
    "title" "text" NOT NULL,
    "short_description" "text",
    "country_code" "text",
    "city" "text",
    "region" "text",
    "formatted_address" "text",
    "latitude" double precision,
    "longitude" double precision,
    "start_at" timestamp with time zone NOT NULL,
    "end_at" timestamp with time zone,
    "category" "text",
    "minimum_age" smallint,
    "maximum_age" smallint,
    "free_entry" boolean,
    "price_note" "text",
    "image_url" "text",
    "review_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "featured" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "events_country_code_check" CHECK (("country_code" = ANY (ARRAY['SK'::"text", 'CZ'::"text"]))),
    CONSTRAINT "events_maximum_age_check" CHECK ((("maximum_age" >= 0) AND ("maximum_age" <= 17))),
    CONSTRAINT "events_minimum_age_check" CHECK ((("minimum_age" >= 0) AND ("minimum_age" <= 17))),
    CONSTRAINT "events_review_status_check" CHECK (("review_status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."experience_categories" (
    "experience_id" "uuid" NOT NULL,
    "category_code" "text" NOT NULL,
    "is_primary" boolean DEFAULT false NOT NULL,
    "confidence" numeric(4,3) DEFAULT 1.000 NOT NULL,
    CONSTRAINT "experience_categories_confidence_check" CHECK ((("confidence" >= (0)::numeric) AND ("confidence" <= (1)::numeric)))
);


ALTER TABLE "public"."experience_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."experience_occurrences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "experience_id" "uuid" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone,
    "doors_open_at" timestamp with time zone,
    "timezone" "text" DEFAULT 'Europe/Bratislava'::"text" NOT NULL,
    "all_day" boolean DEFAULT false NOT NULL,
    "status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "previous_starts_at" timestamp with time zone,
    "recurrence_rule" "text",
    "capacity" integer,
    "sales_start_at" timestamp with time zone,
    "sales_end_at" timestamp with time zone,
    "occurrence_key" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "experience_occurrences_capacity_check" CHECK ((("capacity" IS NULL) OR ("capacity" >= 0))),
    CONSTRAINT "experience_occurrences_check" CHECK ((("ends_at" IS NULL) OR ("ends_at" >= "starts_at"))),
    CONSTRAINT "experience_occurrences_status_check" CHECK (("status" = ANY (ARRAY['scheduled'::"text", 'cancelled'::"text", 'postponed'::"text", 'rescheduled'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."experience_occurrences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."experiences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "kind" "text" NOT NULL,
    "title" "text" NOT NULL,
    "normalized_title" "text" DEFAULT ''::"text" NOT NULL,
    "summary" "text",
    "description" "text",
    "language_code" "text" DEFAULT 'sk'::"text" NOT NULL,
    "venue_id" "uuid",
    "organizer_id" "uuid",
    "official_url" "text",
    "primary_ticket_url" "text",
    "hero_image_url" "text",
    "age_min" smallint,
    "age_max" smallint,
    "indoor" boolean,
    "outdoor" boolean,
    "stroller_friendly" boolean,
    "wheelchair_accessible" boolean,
    "pet_friendly" boolean,
    "free_entry" boolean,
    "family_score" smallint DEFAULT 50 NOT NULL,
    "quality_score" smallint DEFAULT 0 NOT NULL,
    "publication_status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "lifecycle_status" "text" DEFAULT 'active'::"text" NOT NULL,
    "dedupe_key" "text",
    "source_freshness_at" timestamp with time zone,
    "last_verified_at" timestamp with time zone,
    "first_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "published_at" timestamp with time zone,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "experiences_age_max_check" CHECK ((("age_max" IS NULL) OR (("age_max" >= 0) AND ("age_max" <= 17)))),
    CONSTRAINT "experiences_age_min_check" CHECK ((("age_min" IS NULL) OR (("age_min" >= 0) AND ("age_min" <= 17)))),
    CONSTRAINT "experiences_check" CHECK ((("age_min" IS NULL) OR ("age_max" IS NULL) OR ("age_max" >= "age_min"))),
    CONSTRAINT "experiences_family_score_check" CHECK ((("family_score" >= 0) AND ("family_score" <= 100))),
    CONSTRAINT "experiences_kind_check" CHECK (("kind" = ANY (ARRAY['attraction'::"text", 'event'::"text"]))),
    CONSTRAINT "experiences_lifecycle_status_check" CHECK (("lifecycle_status" = ANY (ARRAY['active'::"text", 'scheduled'::"text", 'cancelled'::"text", 'postponed'::"text", 'rescheduled'::"text", 'completed'::"text", 'closed'::"text"]))),
    CONSTRAINT "experiences_publication_status_check" CHECK (("publication_status" = ANY (ARRAY['draft'::"text", 'review'::"text", 'published'::"text", 'archived'::"text"]))),
    CONSTRAINT "experiences_quality_score_check" CHECK ((("quality_score" >= 0) AND ("quality_score" <= 100)))
);


ALTER TABLE "public"."experiences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ticket_offers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "experience_id" "uuid" NOT NULL,
    "occurrence_id" "uuid",
    "source_id" "uuid" NOT NULL,
    "external_offer_id" "text",
    "offer_name" "text" NOT NULL,
    "audience_type" "text" DEFAULT 'general'::"text" NOT NULL,
    "age_min" smallint,
    "age_max" smallint,
    "price_min" numeric(12,2),
    "price_max" numeric(12,2),
    "currency" character(3) DEFAULT 'EUR'::"bpchar" NOT NULL,
    "free_entry" boolean DEFAULT false NOT NULL,
    "fees_included" boolean,
    "availability" "text" DEFAULT 'unknown'::"text" NOT NULL,
    "purchase_url" "text",
    "source_url" "text",
    "is_official" boolean DEFAULT false NOT NULL,
    "confidence" numeric(4,3) DEFAULT 0.500 NOT NULL,
    "valid_from" timestamp with time zone,
    "valid_until" timestamp with time zone,
    "checked_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ticket_offers_age_max_check" CHECK ((("age_max" IS NULL) OR (("age_max" >= 0) AND ("age_max" <= 120)))),
    CONSTRAINT "ticket_offers_age_min_check" CHECK ((("age_min" IS NULL) OR (("age_min" >= 0) AND ("age_min" <= 120)))),
    CONSTRAINT "ticket_offers_audience_type_check" CHECK (("audience_type" = ANY (ARRAY['general'::"text", 'adult'::"text", 'child'::"text", 'student'::"text", 'senior'::"text", 'family'::"text", 'group'::"text", 'vip'::"text", 'disabled'::"text", 'companion'::"text", 'other'::"text"]))),
    CONSTRAINT "ticket_offers_availability_check" CHECK (("availability" = ANY (ARRAY['available'::"text", 'limited'::"text", 'sold_out'::"text", 'unavailable'::"text", 'unknown'::"text"]))),
    CONSTRAINT "ticket_offers_check" CHECK ((("age_min" IS NULL) OR ("age_max" IS NULL) OR ("age_max" >= "age_min"))),
    CONSTRAINT "ticket_offers_check1" CHECK ((("price_min" IS NULL) OR ("price_max" IS NULL) OR ("price_max" >= "price_min"))),
    CONSTRAINT "ticket_offers_confidence_check" CHECK ((("confidence" >= (0)::numeric) AND ("confidence" <= (1)::numeric))),
    CONSTRAINT "ticket_offers_currency_check" CHECK (("currency" ~ '^[A-Z]{3}$'::"text")),
    CONSTRAINT "ticket_offers_price_max_check" CHECK ((("price_max" IS NULL) OR ("price_max" >= (0)::numeric))),
    CONSTRAINT "ticket_offers_price_min_check" CHECK ((("price_min" IS NULL) OR ("price_min" >= (0)::numeric)))
);


ALTER TABLE "public"."ticket_offers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."venues" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" DEFAULT ''::"text" NOT NULL,
    "google_place_id" "text",
    "external_slug" "text",
    "formatted_address" "text",
    "street" "text",
    "city" "text",
    "district" "text",
    "region" "text",
    "postal_code" "text",
    "country_code" "text" NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "location" "extensions"."geography"(Point,4326),
    "timezone" "text" DEFAULT 'Europe/Bratislava'::"text" NOT NULL,
    "website_url" "text",
    "phone" "text",
    "email" "text",
    "opening_hours" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "accessibility" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "parking" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "public_transport" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "last_verified_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "venues_country_code_check" CHECK (("country_code" ~ '^[A-Z]{2}$'::"text")),
    CONSTRAINT "venues_latitude_check" CHECK ((("latitude" IS NULL) OR (("latitude" >= ('-90'::integer)::double precision) AND ("latitude" <= (90)::double precision)))),
    CONSTRAINT "venues_longitude_check" CHECK ((("longitude" IS NULL) OR (("longitude" >= ('-180'::integer)::double precision) AND ("longitude" <= (180)::double precision))))
);


ALTER TABLE "public"."venues" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."experience_feed" WITH ("security_invoker"='true') AS
 SELECT "e"."id",
    "e"."kind",
    "e"."title",
    "e"."summary",
    "e"."description",
    "e"."hero_image_url",
    "e"."age_min",
    "e"."age_max",
    "e"."indoor",
    "e"."outdoor",
    "e"."stroller_friendly",
    "e"."wheelchair_accessible",
    "e"."free_entry",
    "e"."family_score",
    "e"."quality_score",
    "e"."lifecycle_status",
    "v"."id" AS "venue_id",
    "v"."name" AS "venue_name",
    "v"."formatted_address",
    "v"."city",
    "v"."region",
    "v"."country_code",
    "v"."latitude",
    "v"."longitude",
    "v"."timezone",
    "primary_category"."code" AS "primary_category_code",
    "primary_category"."name_sk" AS "primary_category_name",
    "primary_category"."emoji" AS "primary_category_emoji",
    "next_occurrence"."id" AS "next_occurrence_id",
    "next_occurrence"."starts_at" AS "next_starts_at",
    "next_occurrence"."ends_at" AS "next_ends_at",
    "next_occurrence"."all_day" AS "next_all_day",
    "next_occurrence"."status" AS "next_occurrence_status",
    "best_offer"."price_min",
    "best_offer"."price_max",
    "best_offer"."currency",
    "best_offer"."offer_name",
    "best_offer"."audience_type",
    "best_offer"."purchase_url",
    "best_offer"."checked_at" AS "price_checked_at",
    "e"."source_freshness_at",
    "e"."last_verified_at",
    "e"."updated_at"
   FROM (((("public"."experiences" "e"
     LEFT JOIN "public"."venues" "v" ON (("v"."id" = "e"."venue_id")))
     LEFT JOIN LATERAL ( SELECT "c"."code",
            "c"."name_sk",
            "c"."emoji"
           FROM ("public"."experience_categories" "ec"
             JOIN "public"."categories" "c" ON (("c"."code" = "ec"."category_code")))
          WHERE ("ec"."experience_id" = "e"."id")
          ORDER BY "ec"."is_primary" DESC, "c"."sort_order"
         LIMIT 1) "primary_category" ON (true))
     LEFT JOIN LATERAL ( SELECT "o"."id",
            "o"."experience_id",
            "o"."starts_at",
            "o"."ends_at",
            "o"."doors_open_at",
            "o"."timezone",
            "o"."all_day",
            "o"."status",
            "o"."previous_starts_at",
            "o"."recurrence_rule",
            "o"."capacity",
            "o"."sales_start_at",
            "o"."sales_end_at",
            "o"."occurrence_key",
            "o"."active",
            "o"."created_at",
            "o"."updated_at"
           FROM "public"."experience_occurrences" "o"
          WHERE (("o"."experience_id" = "e"."id") AND ("o"."active" = true) AND ("o"."status" = ANY (ARRAY['scheduled'::"text", 'rescheduled'::"text"])) AND (COALESCE("o"."ends_at", "o"."starts_at") >= "now"()))
          ORDER BY "o"."starts_at"
         LIMIT 1) "next_occurrence" ON (true))
     LEFT JOIN LATERAL ( SELECT "t"."id",
            "t"."experience_id",
            "t"."occurrence_id",
            "t"."source_id",
            "t"."external_offer_id",
            "t"."offer_name",
            "t"."audience_type",
            "t"."age_min",
            "t"."age_max",
            "t"."price_min",
            "t"."price_max",
            "t"."currency",
            "t"."free_entry",
            "t"."fees_included",
            "t"."availability",
            "t"."purchase_url",
            "t"."source_url",
            "t"."is_official",
            "t"."confidence",
            "t"."valid_from",
            "t"."valid_until",
            "t"."checked_at",
            "t"."active",
            "t"."created_at",
            "t"."updated_at"
           FROM "public"."ticket_offers" "t"
          WHERE (("t"."experience_id" = "e"."id") AND ("t"."active" = true) AND ("t"."availability" <> ALL (ARRAY['sold_out'::"text", 'unavailable'::"text"])) AND (("t"."valid_until" IS NULL) OR ("t"."valid_until" >= "now"())) AND (("t"."occurrence_id" IS NULL) OR ("t"."occurrence_id" = "next_occurrence"."id")))
          ORDER BY "t"."is_official" DESC, "t"."confidence" DESC, "t"."price_min", "t"."checked_at" DESC
         LIMIT 1) "best_offer" ON (true))
  WHERE (("e"."publication_status" = 'published'::"text") AND ("e"."active" = true));


ALTER VIEW "public"."experience_feed" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."experience_sources" (
    "experience_id" "uuid" NOT NULL,
    "source_id" "uuid" NOT NULL,
    "external_id" "text" NOT NULL,
    "source_url" "text",
    "is_primary" boolean DEFAULT false NOT NULL,
    "is_official" boolean DEFAULT false NOT NULL,
    "first_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_verified_at" timestamp with time zone
);


ALTER TABLE "public"."experience_sources" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."media_assets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "experience_id" "uuid",
    "venue_id" "uuid",
    "source_id" "uuid",
    "media_type" "text" NOT NULL,
    "url" "text" NOT NULL,
    "thumbnail_url" "text",
    "width" integer,
    "height" integer,
    "alt_text" "text",
    "attribution" "text",
    "license" "text",
    "sort_order" integer DEFAULT 100 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "media_assets_check" CHECK ((("experience_id" IS NOT NULL) OR ("venue_id" IS NOT NULL))),
    CONSTRAINT "media_assets_height_check" CHECK ((("height" IS NULL) OR ("height" > 0))),
    CONSTRAINT "media_assets_media_type_check" CHECK (("media_type" = ANY (ARRAY['image'::"text", 'video'::"text", 'document'::"text"]))),
    CONSTRAINT "media_assets_width_check" CHECK ((("width" IS NULL) OR ("width" > 0)))
);


ALTER TABLE "public"."media_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organizers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" DEFAULT ''::"text" NOT NULL,
    "website_url" "text",
    "email" "text",
    "phone" "text",
    "country_code" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "organizers_country_code_check" CHECK ((("country_code" IS NULL) OR ("country_code" ~ '^[A-Z]{2}$'::"text")))
);


ALTER TABLE "public"."organizers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."places" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "google_place_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "country_code" "text",
    "city" "text",
    "region" "text",
    "formatted_address" "text",
    "latitude" double precision NOT NULL,
    "longitude" double precision NOT NULL,
    "primary_type" "text",
    "types" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "short_description" "text",
    "family_score" smallint DEFAULT 0 NOT NULL,
    "minimum_age" smallint,
    "maximum_age" smallint,
    "is_indoor" boolean,
    "is_outdoor" boolean,
    "stroller_friendly" boolean,
    "price_note" "text",
    "parking_note" "text",
    "website_url" "text",
    "google_maps_url" "text",
    "phone" "text",
    "rating" numeric(2,1),
    "user_rating_count" integer DEFAULT 0 NOT NULL,
    "opening_hours" "jsonb",
    "photo_references" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "business_status" "text",
    "review_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "featured" boolean DEFAULT false NOT NULL,
    "discovered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_synced_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "places_country_code_check" CHECK (("country_code" = ANY (ARRAY['SK'::"text", 'CZ'::"text"]))),
    CONSTRAINT "places_family_score_check" CHECK ((("family_score" >= 0) AND ("family_score" <= 100))),
    CONSTRAINT "places_maximum_age_check" CHECK ((("maximum_age" >= 0) AND ("maximum_age" <= 17))),
    CONSTRAINT "places_minimum_age_check" CHECK ((("minimum_age" >= 0) AND ("minimum_age" <= 17))),
    CONSTRAINT "places_rating_check" CHECK ((("rating" >= (0)::numeric) AND ("rating" <= (5)::numeric))),
    CONSTRAINT "places_review_status_check" CHECK (("review_status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "places_user_rating_count_check" CHECK (("user_rating_count" >= 0))
);


ALTER TABLE "public"."places" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_cache" (
    "id" bigint NOT NULL,
    "cache_key" "text" NOT NULL,
    "origin_place_id" "text" NOT NULL,
    "origin_name" "text",
    "destination_place_id" "uuid" NOT NULL,
    "travel_mode" "text" NOT NULL,
    "distance_meters" integer,
    "duration_minutes" integer,
    "transfers" integer,
    "walking_minutes" integer,
    "departure_at" timestamp with time zone,
    "route_summary" "text",
    "fetched_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone,
    CONSTRAINT "route_cache_distance_meters_check" CHECK ((("distance_meters" IS NULL) OR ("distance_meters" >= 0))),
    CONSTRAINT "route_cache_duration_minutes_check" CHECK ((("duration_minutes" IS NULL) OR ("duration_minutes" >= 0))),
    CONSTRAINT "route_cache_transfers_check" CHECK ((("transfers" IS NULL) OR ("transfers" >= 0))),
    CONSTRAINT "route_cache_travel_mode_check" CHECK (("travel_mode" = ANY (ARRAY['DRIVE'::"text", 'TRANSIT'::"text", 'WALK'::"text"]))),
    CONSTRAINT "route_cache_walking_minutes_check" CHECK ((("walking_minutes" IS NULL) OR ("walking_minutes" >= 0)))
);


ALTER TABLE "public"."route_cache" OWNER TO "postgres";


ALTER TABLE "public"."route_cache" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."route_cache_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."sources" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "source_type" "text" NOT NULL,
    "website_url" "text",
    "trust_level" smallint DEFAULT 50 NOT NULL,
    "is_official" boolean DEFAULT false NOT NULL,
    "attribution_required" boolean DEFAULT false NOT NULL,
    "default_cache_ttl_seconds" integer DEFAULT 86400 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sources_default_cache_ttl_seconds_check" CHECK (("default_cache_ttl_seconds" >= 0)),
    CONSTRAINT "sources_source_type_check" CHECK (("source_type" = ANY (ARRAY['api'::"text", 'feed'::"text", 'jsonld'::"text", 'html'::"text", 'pdf'::"text", 'search'::"text", 'manual'::"text", 'partner'::"text"]))),
    CONSTRAINT "sources_trust_level_check" CHECK ((("trust_level" >= 0) AND ("trust_level" <= 100)))
);


ALTER TABLE "public"."sources" OWNER TO "postgres";


ALTER TABLE ONLY "private"."dedupe_candidates"
    ADD CONSTRAINT "dedupe_candidates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."ingestion_runs"
    ADD CONSTRAINT "ingestion_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."place_candidates"
    ADD CONSTRAINT "place_candidates_google_place_id_key" UNIQUE ("google_place_id");



ALTER TABLE ONLY "private"."place_candidates"
    ADD CONSTRAINT "place_candidates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."quality_issues"
    ADD CONSTRAINT "quality_issues_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."schema_versions"
    ADD CONSTRAINT "schema_versions_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "private"."source_connectors"
    ADD CONSTRAINT "source_connectors_connector_key_key" UNIQUE ("connector_key");



ALTER TABLE ONLY "private"."source_connectors"
    ADD CONSTRAINT "source_connectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."source_connectors"
    ADD CONSTRAINT "source_connectors_source_id_key" UNIQUE ("source_id");



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_source_id_entity_kind_external_id_key" UNIQUE ("source_id", "entity_kind", "external_id");



ALTER TABLE ONLY "private"."sync_runs"
    ADD CONSTRAINT "sync_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "private"."ticket_offer_snapshots"
    ADD CONSTRAINT "ticket_offer_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("code");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."experience_categories"
    ADD CONSTRAINT "experience_categories_pkey" PRIMARY KEY ("experience_id", "category_code");



ALTER TABLE ONLY "public"."experience_occurrences"
    ADD CONSTRAINT "experience_occurrences_experience_id_occurrence_key_key" UNIQUE ("experience_id", "occurrence_key");



ALTER TABLE ONLY "public"."experience_occurrences"
    ADD CONSTRAINT "experience_occurrences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."experience_sources"
    ADD CONSTRAINT "experience_sources_pkey" PRIMARY KEY ("experience_id", "source_id", "external_id");



ALTER TABLE ONLY "public"."experience_sources"
    ADD CONSTRAINT "experience_sources_source_id_external_id_key" UNIQUE ("source_id", "external_id");



ALTER TABLE ONLY "public"."experiences"
    ADD CONSTRAINT "experiences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizers"
    ADD CONSTRAINT "organizers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."places"
    ADD CONSTRAINT "places_google_place_id_key" UNIQUE ("google_place_id");



ALTER TABLE ONLY "public"."places"
    ADD CONSTRAINT "places_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_cache"
    ADD CONSTRAINT "route_cache_cache_key_key" UNIQUE ("cache_key");



ALTER TABLE ONLY "public"."route_cache"
    ADD CONSTRAINT "route_cache_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sources"
    ADD CONSTRAINT "sources_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."sources"
    ADD CONSTRAINT "sources_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ticket_offers"
    ADD CONSTRAINT "ticket_offers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."events"
    ADD CONSTRAINT "unique_external_event" UNIQUE ("source_name", "external_id");



ALTER TABLE ONLY "public"."venues"
    ADD CONSTRAINT "venues_pkey" PRIMARY KEY ("id");



CREATE INDEX "candidates_review_status_index" ON "private"."place_candidates" USING "btree" ("review_status");



CREATE UNIQUE INDEX "dedupe_pair_unique" ON "private"."dedupe_candidates" USING "btree" (LEAST("left_source_record_id", "right_source_record_id"), GREATEST("left_source_record_id", "right_source_record_id"), "entity_kind");



CREATE INDEX "ingestion_runs_connector_started_idx" ON "private"."ingestion_runs" USING "btree" ("connector_id", "started_at" DESC);



CREATE INDEX "offer_snapshots_offer_time_idx" ON "private"."ticket_offer_snapshots" USING "btree" ("ticket_offer_id", "captured_at" DESC);



CREATE INDEX "quality_issues_open_idx" ON "private"."quality_issues" USING "btree" ("severity", "created_at" DESC) WHERE ("resolved" = false);



CREATE INDEX "source_records_payload_hash_idx" ON "private"."source_records" USING "btree" ("payload_hash") WHERE ("payload_hash" IS NOT NULL);



CREATE INDEX "source_records_processing_idx" ON "private"."source_records" USING "btree" ("processing_status", "fetched_at");



CREATE INDEX "source_records_source_last_seen_idx" ON "private"."source_records" USING "btree" ("source_id", "last_seen_at" DESC);



CREATE INDEX "events_country_city_index" ON "public"."events" USING "btree" ("country_code", "city");



CREATE INDEX "events_date_index" ON "public"."events" USING "btree" ("start_at");



CREATE INDEX "events_review_status_index" ON "public"."events" USING "btree" ("review_status");



CREATE UNIQUE INDEX "experience_one_primary_category" ON "public"."experience_categories" USING "btree" ("experience_id") WHERE ("is_primary" = true);



CREATE UNIQUE INDEX "experience_one_primary_source" ON "public"."experience_sources" USING "btree" ("experience_id") WHERE ("is_primary" = true);



CREATE INDEX "experiences_dedupe_key_idx" ON "public"."experiences" USING "btree" ("dedupe_key");



CREATE INDEX "experiences_kind_status_idx" ON "public"."experiences" USING "btree" ("kind", "publication_status", "active");



CREATE INDEX "experiences_normalized_title_trgm" ON "public"."experiences" USING "gin" ("normalized_title" "extensions"."gin_trgm_ops");



CREATE INDEX "experiences_organizer_idx" ON "public"."experiences" USING "btree" ("organizer_id");



CREATE INDEX "experiences_text_search_idx" ON "public"."experiences" USING "gin" ("to_tsvector"('"simple"'::"regconfig", ((((COALESCE("title", ''::"text") || ' '::"text") || COALESCE("summary", ''::"text")) || ' '::"text") || COALESCE("description", ''::"text"))));



CREATE INDEX "experiences_venue_idx" ON "public"."experiences" USING "btree" ("venue_id");



CREATE INDEX "media_experience_idx" ON "public"."media_assets" USING "btree" ("experience_id", "sort_order") WHERE (("experience_id" IS NOT NULL) AND ("active" = true));



CREATE INDEX "media_venue_idx" ON "public"."media_assets" USING "btree" ("venue_id", "sort_order") WHERE (("venue_id" IS NOT NULL) AND ("active" = true));



CREATE INDEX "occurrences_experience_status_idx" ON "public"."experience_occurrences" USING "btree" ("experience_id", "status", "active");



CREATE INDEX "occurrences_start_idx" ON "public"."experience_occurrences" USING "btree" ("starts_at");



CREATE INDEX "organizers_normalized_name_trgm" ON "public"."organizers" USING "gin" ("normalized_name" "extensions"."gin_trgm_ops");



CREATE INDEX "places_country_city_index" ON "public"."places" USING "btree" ("country_code", "city");



CREATE INDEX "places_family_score_index" ON "public"."places" USING "btree" ("family_score" DESC);



CREATE INDEX "places_location_index" ON "public"."places" USING "btree" ("latitude", "longitude");



CREATE INDEX "places_primary_type_index" ON "public"."places" USING "btree" ("primary_type");



CREATE INDEX "places_review_status_index" ON "public"."places" USING "btree" ("review_status");



CREATE INDEX "route_destination_index" ON "public"."route_cache" USING "btree" ("destination_place_id");



CREATE INDEX "route_expiration_index" ON "public"."route_cache" USING "btree" ("expires_at");



CREATE INDEX "ticket_offers_experience_idx" ON "public"."ticket_offers" USING "btree" ("experience_id", "active", "checked_at" DESC);



CREATE UNIQUE INDEX "ticket_offers_external_unique" ON "public"."ticket_offers" USING "btree" ("source_id", "external_offer_id") WHERE ("external_offer_id" IS NOT NULL);



CREATE INDEX "ticket_offers_occurrence_idx" ON "public"."ticket_offers" USING "btree" ("occurrence_id") WHERE ("occurrence_id" IS NOT NULL);



CREATE INDEX "ticket_offers_price_idx" ON "public"."ticket_offers" USING "btree" ("currency", "price_min") WHERE ("active" = true);



CREATE INDEX "venues_country_city_idx" ON "public"."venues" USING "btree" ("country_code", "city");



CREATE UNIQUE INDEX "venues_google_place_unique" ON "public"."venues" USING "btree" ("google_place_id") WHERE ("google_place_id" IS NOT NULL);



CREATE INDEX "venues_location_gist" ON "public"."venues" USING "gist" ("location");



CREATE INDEX "venues_normalized_name_trgm" ON "public"."venues" USING "gin" ("normalized_name" "extensions"."gin_trgm_ops");



CREATE OR REPLACE TRIGGER "candidates_set_updated_at" BEFORE UPDATE ON "private"."place_candidates" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "connectors_set_updated_at" BEFORE UPDATE ON "private"."source_connectors" FOR EACH ROW EXECUTE FUNCTION "private"."set_updated_at"();



CREATE OR REPLACE TRIGGER "source_records_set_updated_at" BEFORE UPDATE ON "private"."source_records" FOR EACH ROW EXECUTE FUNCTION "private"."set_updated_at"();



CREATE OR REPLACE TRIGGER "events_set_updated_at" BEFORE UPDATE ON "public"."events" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "experiences_prepare_trigger" BEFORE INSERT OR UPDATE ON "public"."experiences" FOR EACH ROW EXECUTE FUNCTION "private"."prepare_experience"();



CREATE OR REPLACE TRIGGER "occurrences_set_updated_at" BEFORE UPDATE ON "public"."experience_occurrences" FOR EACH ROW EXECUTE FUNCTION "private"."set_updated_at"();



CREATE OR REPLACE TRIGGER "organizers_prepare_trigger" BEFORE INSERT OR UPDATE ON "public"."organizers" FOR EACH ROW EXECUTE FUNCTION "private"."prepare_organizer"();



CREATE OR REPLACE TRIGGER "places_set_updated_at" BEFORE UPDATE ON "public"."places" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "sources_set_updated_at" BEFORE UPDATE ON "public"."sources" FOR EACH ROW EXECUTE FUNCTION "private"."set_updated_at"();



CREATE OR REPLACE TRIGGER "ticket_offers_set_updated_at" BEFORE UPDATE ON "public"."ticket_offers" FOR EACH ROW EXECUTE FUNCTION "private"."set_updated_at"();



CREATE OR REPLACE TRIGGER "ticket_offers_validate_occurrence" BEFORE INSERT OR UPDATE ON "public"."ticket_offers" FOR EACH ROW EXECUTE FUNCTION "private"."validate_offer_occurrence"();



CREATE OR REPLACE TRIGGER "venues_prepare_trigger" BEFORE INSERT OR UPDATE ON "public"."venues" FOR EACH ROW EXECUTE FUNCTION "private"."prepare_venue"();



ALTER TABLE ONLY "private"."dedupe_candidates"
    ADD CONSTRAINT "dedupe_candidates_left_source_record_id_fkey" FOREIGN KEY ("left_source_record_id") REFERENCES "private"."source_records"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."dedupe_candidates"
    ADD CONSTRAINT "dedupe_candidates_right_source_record_id_fkey" FOREIGN KEY ("right_source_record_id") REFERENCES "private"."source_records"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."ingestion_runs"
    ADD CONSTRAINT "ingestion_runs_connector_id_fkey" FOREIGN KEY ("connector_id") REFERENCES "private"."source_connectors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."source_connectors"
    ADD CONSTRAINT "source_connectors_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."sources"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_canonical_experience_id_fkey" FOREIGN KEY ("canonical_experience_id") REFERENCES "public"."experiences"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_canonical_occurrence_id_fkey" FOREIGN KEY ("canonical_occurrence_id") REFERENCES "public"."experience_occurrences"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_canonical_offer_id_fkey" FOREIGN KEY ("canonical_offer_id") REFERENCES "public"."ticket_offers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_canonical_venue_id_fkey" FOREIGN KEY ("canonical_venue_id") REFERENCES "public"."venues"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_ingestion_run_id_fkey" FOREIGN KEY ("ingestion_run_id") REFERENCES "private"."ingestion_runs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "private"."source_records"
    ADD CONSTRAINT "source_records_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."sources"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."ticket_offer_snapshots"
    ADD CONSTRAINT "ticket_offer_snapshots_ticket_offer_id_fkey" FOREIGN KEY ("ticket_offer_id") REFERENCES "public"."ticket_offers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_parent_code_fkey" FOREIGN KEY ("parent_code") REFERENCES "public"."categories"("code");



ALTER TABLE ONLY "public"."experience_categories"
    ADD CONSTRAINT "experience_categories_category_code_fkey" FOREIGN KEY ("category_code") REFERENCES "public"."categories"("code");



ALTER TABLE ONLY "public"."experience_categories"
    ADD CONSTRAINT "experience_categories_experience_id_fkey" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."experience_occurrences"
    ADD CONSTRAINT "experience_occurrences_experience_id_fkey" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."experience_sources"
    ADD CONSTRAINT "experience_sources_experience_id_fkey" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."experience_sources"
    ADD CONSTRAINT "experience_sources_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."sources"("id");



ALTER TABLE ONLY "public"."experiences"
    ADD CONSTRAINT "experiences_organizer_id_fkey" FOREIGN KEY ("organizer_id") REFERENCES "public"."organizers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."experiences"
    ADD CONSTRAINT "experiences_venue_id_fkey" FOREIGN KEY ("venue_id") REFERENCES "public"."venues"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_experience_id_fkey" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."sources"("id");



ALTER TABLE ONLY "public"."media_assets"
    ADD CONSTRAINT "media_assets_venue_id_fkey" FOREIGN KEY ("venue_id") REFERENCES "public"."venues"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_cache"
    ADD CONSTRAINT "route_cache_destination_place_id_fkey" FOREIGN KEY ("destination_place_id") REFERENCES "public"."places"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_offers"
    ADD CONSTRAINT "ticket_offers_experience_id_fkey" FOREIGN KEY ("experience_id") REFERENCES "public"."experiences"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_offers"
    ADD CONSTRAINT "ticket_offers_occurrence_id_fkey" FOREIGN KEY ("occurrence_id") REFERENCES "public"."experience_occurrences"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_offers"
    ADD CONSTRAINT "ticket_offers_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."sources"("id");



ALTER TABLE "private"."dedupe_candidates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."ingestion_runs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."place_candidates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."quality_issues" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."schema_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."source_connectors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."source_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."sync_runs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."ticket_offer_snapshots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Read approved active events" ON "public"."events" FOR SELECT TO "authenticated", "anon" USING ((("review_status" = 'approved'::"text") AND ("active" = true) AND (("end_at" IS NULL) OR ("end_at" >= "now"()))));



CREATE POLICY "Read approved active places" ON "public"."places" FOR SELECT TO "authenticated", "anon" USING ((("review_status" = 'approved'::"text") AND ("active" = true)));



CREATE POLICY "Read valid cached routes" ON "public"."route_cache" FOR SELECT TO "authenticated", "anon" USING ((("expires_at" IS NULL) OR ("expires_at" > "now"())));



ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "categories_public_read" ON "public"."categories" FOR SELECT TO "authenticated", "anon" USING (("active" = true));



ALTER TABLE "public"."events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."experience_categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "experience_categories_public_read" ON "public"."experience_categories" FOR SELECT TO "authenticated", "anon" USING ((EXISTS ( SELECT 1
   FROM "public"."experiences" "e"
  WHERE (("e"."id" = "experience_categories"."experience_id") AND ("e"."active" = true) AND ("e"."publication_status" = 'published'::"text")))));



ALTER TABLE "public"."experience_occurrences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."experience_sources" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "experience_sources_public_read" ON "public"."experience_sources" FOR SELECT TO "authenticated", "anon" USING ((EXISTS ( SELECT 1
   FROM "public"."experiences" "e"
  WHERE (("e"."id" = "experience_sources"."experience_id") AND ("e"."active" = true) AND ("e"."publication_status" = 'published'::"text")))));



ALTER TABLE "public"."experiences" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "experiences_public_read" ON "public"."experiences" FOR SELECT TO "authenticated", "anon" USING ((("active" = true) AND ("publication_status" = 'published'::"text")));



ALTER TABLE "public"."media_assets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "media_public_read" ON "public"."media_assets" FOR SELECT TO "authenticated", "anon" USING ((("active" = true) AND (("experience_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "public"."experiences" "e"
  WHERE (("e"."id" = "media_assets"."experience_id") AND ("e"."active" = true) AND ("e"."publication_status" = 'published'::"text")))))));



CREATE POLICY "occurrences_public_read" ON "public"."experience_occurrences" FOR SELECT TO "authenticated", "anon" USING ((("active" = true) AND (EXISTS ( SELECT 1
   FROM "public"."experiences" "e"
  WHERE (("e"."id" = "experience_occurrences"."experience_id") AND ("e"."active" = true) AND ("e"."publication_status" = 'published'::"text"))))));



CREATE POLICY "offers_public_read" ON "public"."ticket_offers" FOR SELECT TO "authenticated", "anon" USING ((("active" = true) AND (("valid_until" IS NULL) OR ("valid_until" >= "now"())) AND (EXISTS ( SELECT 1
   FROM "public"."experiences" "e"
  WHERE (("e"."id" = "ticket_offers"."experience_id") AND ("e"."active" = true) AND ("e"."publication_status" = 'published'::"text"))))));



ALTER TABLE "public"."organizers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organizers_public_read" ON "public"."organizers" FOR SELECT TO "authenticated", "anon" USING (("active" = true));



ALTER TABLE "public"."places" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."route_cache" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sources" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sources_public_read" ON "public"."sources" FOR SELECT TO "authenticated", "anon" USING (("active" = true));



ALTER TABLE "public"."ticket_offers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."venues" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "venues_public_read" ON "public"."venues" FOR SELECT TO "authenticated", "anon" USING (("active" = true));



GRANT USAGE ON SCHEMA "private" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "private"."normalize_text"("input_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "private"."prepare_experience"() TO "service_role";



GRANT ALL ON FUNCTION "private"."prepare_organizer"() TO "service_role";



GRANT ALL ON FUNCTION "private"."prepare_venue"() TO "service_role";



GRANT ALL ON FUNCTION "private"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "private"."validate_offer_occurrence"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."catalog_private_bridge"("p_action" "text", "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."catalog_private_bridge"("p_action" "text", "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."search_experiences"("p_latitude" double precision, "p_longitude" double precision, "p_radius_km" double precision, "p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_kinds" "text"[], "p_category_codes" "text"[], "p_min_child_age" smallint, "p_max_child_age" smallint, "p_free_only" boolean, "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."search_experiences"("p_latitude" double precision, "p_longitude" double precision, "p_radius_km" double precision, "p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_kinds" "text"[], "p_category_codes" "text"[], "p_min_child_age" smallint, "p_max_child_age" smallint, "p_free_only" boolean, "p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."search_experiences"("p_latitude" double precision, "p_longitude" double precision, "p_radius_km" double precision, "p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_kinds" "text"[], "p_category_codes" "text"[], "p_min_child_age" smallint, "p_max_child_age" smallint, "p_free_only" boolean, "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_experiences"("p_latitude" double precision, "p_longitude" double precision, "p_radius_km" double precision, "p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_kinds" "text"[], "p_category_codes" "text"[], "p_min_child_age" smallint, "p_max_child_age" smallint, "p_free_only" boolean, "p_limit" integer, "p_offset" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON TABLE "private"."dedupe_candidates" TO "service_role";



GRANT ALL ON TABLE "private"."ingestion_runs" TO "service_role";



GRANT ALL ON TABLE "private"."place_candidates" TO "service_role";



GRANT ALL ON TABLE "private"."quality_issues" TO "service_role";



GRANT ALL ON TABLE "private"."source_connectors" TO "service_role";



GRANT ALL ON TABLE "private"."source_records" TO "service_role";



GRANT ALL ON TABLE "private"."sync_runs" TO "service_role";



GRANT ALL ON SEQUENCE "private"."sync_runs_id_seq" TO "service_role";



GRANT ALL ON TABLE "private"."ticket_offer_snapshots" TO "service_role";



GRANT ALL ON SEQUENCE "private"."ticket_offer_snapshots_id_seq" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."categories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."events" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."events" TO "authenticated";
GRANT ALL ON TABLE "public"."events" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experience_categories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experience_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."experience_categories" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experience_occurrences" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experience_occurrences" TO "authenticated";
GRANT ALL ON TABLE "public"."experience_occurrences" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experiences" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experiences" TO "authenticated";
GRANT ALL ON TABLE "public"."experiences" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ticket_offers" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ticket_offers" TO "authenticated";
GRANT ALL ON TABLE "public"."ticket_offers" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."venues" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."venues" TO "authenticated";
GRANT ALL ON TABLE "public"."venues" TO "service_role";



GRANT ALL ON TABLE "public"."experience_feed" TO "anon";
GRANT ALL ON TABLE "public"."experience_feed" TO "authenticated";
GRANT ALL ON TABLE "public"."experience_feed" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experience_sources" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."experience_sources" TO "authenticated";
GRANT ALL ON TABLE "public"."experience_sources" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."media_assets" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."media_assets" TO "authenticated";
GRANT ALL ON TABLE "public"."media_assets" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organizers" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organizers" TO "authenticated";
GRANT ALL ON TABLE "public"."organizers" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."places" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."places" TO "authenticated";
GRANT ALL ON TABLE "public"."places" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."route_cache" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."route_cache" TO "authenticated";
GRANT ALL ON TABLE "public"."route_cache" TO "service_role";



GRANT ALL ON SEQUENCE "public"."route_cache_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."route_cache_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."route_cache_id_seq" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."sources" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."sources" TO "authenticated";
GRANT ALL ON TABLE "public"."sources" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







