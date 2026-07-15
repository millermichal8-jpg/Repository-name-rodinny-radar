import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type SyncAction = "preview" | "sync";

type SyncRequest = {
  action?: SyncAction;
  countryCodes?: string[];
  startDateTime?: string;
  endDateTime?: string;
  pageSize?: number;
  maxPagesPerCountry?: number;
  keyword?: string;
  classificationName?: string;
};

type JsonObject = Record<string, unknown>;

type SyncStats = {
  fetched: number;
  inserted: number;
  updated: number;
  skipped: number;
  errors: number;
  countries: Record<string, {
    pagesFetched: number;
    totalElements: number;
    eventsFetched: number;
  }>;
  errorMessages: string[];
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sync-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const allowedCountries = new Set(["SK", "CZ"]);

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getObject(value: unknown): JsonObject | null {
  return isObject(value) ? value : null;
}

function getArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function getString(object: JsonObject | null, key: string): string | null {
  if (!object) return null;
  const value = object[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function getNumber(object: JsonObject | null, key: string): number | null {
  if (!object) return null;
  const value = object[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function getBoolean(object: JsonObject | null, key: string): boolean | null {
  if (!object) return null;
  const value = object[key];
  return typeof value === "boolean" ? value : null;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function normalizeText(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function compactText(...parts: Array<string | null | undefined>) {
  const unique = new Set<string>();
  for (const part of parts) {
    const clean = part?.replace(/\s+/g, " ").trim();
    if (clean) unique.add(clean);
  }
  return [...unique].join("\n\n").slice(0, 12000) || null;
}

function toTicketmasterDateTime(
  value: string | null,
  fallback: Date,
) {
  const parsed = value ? new Date(value) : fallback;
  const safeDate = Number.isNaN(parsed.getTime())
    ? fallback
    : parsed;

  // Ticketmaster dokumentuje čas bez milisekúnd:
  // YYYY-MM-DDTHH:mm:ssZ
  return safeDate
    .toISOString()
    .replace(/\.\d{3}Z$/, "Z");
}

function addDays(date: Date, days: number) {
  return new Date(date.getTime() + days * 86_400_000);
}

function combineLocalDateTime(localDate: string | null, localTime: string | null) {
  if (!localDate) return null;
  const candidate = `${localDate}T${localTime ?? "00:00:00"}Z`;
  const parsed = new Date(candidate);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function mapLifecycleStatus(statusCode: string | null) {
  switch (statusCode?.toLowerCase()) {
    case "canceled":
      return "cancelled";
    case "postponed":
      return "postponed";
    case "rescheduled":
      return "rescheduled";
    case "offsale":
      return "scheduled";
    case "onsale":
    default:
      return "scheduled";
  }
}

function mapOccurrenceStatus(statusCode: string | null) {
  switch (statusCode?.toLowerCase()) {
    case "canceled":
      return "cancelled";
    case "postponed":
      return "postponed";
    case "rescheduled":
      return "rescheduled";
    default:
      return "scheduled";
  }
}

function mapAvailability(statusCode: string | null) {
  switch (statusCode?.toLowerCase()) {
    case "onsale":
      return "available";
    case "offsale":
      return "unavailable";
    case "canceled":
      return "unavailable";
    default:
      return "unknown";
  }
}

function chooseImage(imagesValue: unknown) {
  const images = getArray(imagesValue)
    .map(getObject)
    .filter((item): item is JsonObject => Boolean(item))
    .map((item) => ({
      url: getString(item, "url"),
      width: getNumber(item, "width") ?? 0,
      height: getNumber(item, "height") ?? 0,
      ratio: getString(item, "ratio"),
      fallback: getBoolean(item, "fallback") ?? false,
    }))
    .filter((item) => item.url && !item.fallback);

  images.sort((a, b) => {
    const aRatio = a.ratio === "16_9" ? 1 : 0;
    const bRatio = b.ratio === "16_9" ? 1 : 0;
    return bRatio - aRatio || b.width * b.height - a.width * a.height;
  });

  return images[0]?.url ?? null;
}

function classificationInfo(event: JsonObject) {
  const classifications = getArray(event["classifications"])
    .map(getObject)
    .filter((item): item is JsonObject => Boolean(item));

  const first = classifications[0] ?? null;
  const segment = getObject(first?.["segment"]);
  const genre = getObject(first?.["genre"]);
  const subGenre = getObject(first?.["subGenre"]);

  const names = [
    getString(segment, "name"),
    getString(genre, "name"),
    getString(subGenre, "name"),
  ].filter((value): value is string => Boolean(value));

  const combined = normalizeText(names.join(" "));
  const family = classifications.some((item) => getBoolean(item, "family") === true) ||
    /family|children|kids|dets|rodin/.test(combined);

  let categoryCode = "other";
  if (/theatre|arts|theater|performance|circus/.test(combined)) categoryCode = "theatre";
  if (/music|concert/.test(combined)) categoryCode = "music";
  if (/sport/.test(combined)) categoryCode = "sport";
  if (/film|cinema/.test(combined)) categoryCode = "cinema";
  if (/festival|fair|expo/.test(combined)) categoryCode = "festival";
  if (/museum|science|education/.test(combined)) categoryCode = "education";
  if (family && categoryCode === "other") categoryCode = "community";

  return {
    categoryCode,
    family,
    label: names.join(" • ") || null,
  };
}

function qualityScore(event: JsonObject, venue: JsonObject | null, startAt: string | null) {
  let score = 20;
  if (getString(event, "name")) score += 15;
  if (startAt) score += 15;
  if (venue) score += 15;
  if (chooseImage(event["images"])) score += 10;
  if (getString(event, "url")) score += 10;
  if (getArray(event["priceRanges"]).length > 0) score += 10;
  if (getString(event, "info") || getString(event, "pleaseNote")) score += 5;
  return clamp(score, 0, 100);
}

async function sha256(value: unknown) {
  const encoded = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function readSupabaseSecretKey() {
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

async function callPrivateBridge<T>(
  supabase: ReturnType<typeof createClient>,
  action: string,
  payload: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await supabase.rpc("catalog_private_bridge", {
    p_action: action,
    p_payload: payload,
  });

  if (error) {
    throw new Error(`Private bridge ${action}: ${error.message}`);
  }

  return data as T;
}

async function fetchTicketmasterPage(
  apiKey: string,
  countryCode: string,
  page: number,
  options: Required<Pick<SyncRequest, "startDateTime" | "endDateTime" | "pageSize">> &
    Pick<SyncRequest, "keyword" | "classificationName">,
) {
  const params = new URLSearchParams({
    apikey: apiKey,
    countryCode,
    startDateTime: options.startDateTime,
    endDateTime: options.endDateTime,
    size: String(options.pageSize),
    page: String(page),
    sort: "date,asc",
    includeTest: "no",
  });

  if (options.keyword?.trim()) params.set("keyword", options.keyword.trim());
  if (options.classificationName?.trim()) {
    params.set("classificationName", options.classificationName.trim());
  }

  const response = await fetch(
    `https://app.ticketmaster.com/discovery/v2/events.json?${params.toString()}`,
  );
  const raw = await response.text();
  let data: unknown = {};
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    throw new Error(`Ticketmaster vrátil neplatný JSON (${response.status}).`);
  }

  if (!response.ok) {
    const fault = isObject(data)
      ? getObject(data["fault"])
      : null;

    const errorItems = isObject(data)
      ? getArray(data["errors"])
          .map(getObject)
          .filter((item): item is JsonObject => Boolean(item))
      : [];

    const errorMessages = errorItems
      .map((item) =>
        getString(item, "detail") ??
        getString(item, "message") ??
        getString(item, "code")
      )
      .filter((item): item is string => Boolean(item));

    const detail = isObject(data)
      ? (
          getString(fault, "faultstring") ??
          getString(data, "message") ??
          errorMessages.join(" | ")
        )
      : null;

    const safeRaw = raw
      .replaceAll(apiKey, "[API_KEY_SKRYTY]")
      .slice(0, 1200);

    throw new Error(
      `Ticketmaster ${countryCode} HTTP ${response.status}: ` +
      `${detail ?? safeRaw ?? "Neznáma chyba."}`,
    );
  }

  return getObject(data) ?? {};
}

async function findOrCreateVenue(
  supabase: ReturnType<typeof createClient>,
  sourceId: string,
  venue: JsonObject | null,
) {
  if (!venue) return null;

  const externalId = getString(venue, "id");
  if (!externalId) return null;

  const sourceRecord = await callPrivateBridge<{
    found: boolean;
    canonicalVenueId?: string | null;
  }>(supabase, "get_source_record", {
    sourceId,
    entityKind: "venue",
    externalId,
  });

  const city = getObject(venue["city"]);
  const state = getObject(venue["state"]);
  const country = getObject(venue["country"]);
  const address = getObject(venue["address"]);
  const location = getObject(venue["location"]);

  const venueRow = {
    name: getString(venue, "name") ?? "Neznáme miesto",
    external_slug: externalId,
    formatted_address: [
      getString(address, "line1"),
      getString(city, "name"),
      getString(state, "name"),
      getString(country, "name"),
    ].filter(Boolean).join(", ") || null,
    street: getString(address, "line1"),
    city: getString(city, "name"),
    region: getString(state, "name"),
    postal_code: getString(venue, "postalCode"),
    country_code: getString(country, "countryCode") ?? "SK",
    latitude: getNumber(location, "latitude"),
    longitude: getNumber(location, "longitude"),
    timezone: getString(venue, "timezone") ?? "Europe/Bratislava",
    website_url: getString(venue, "url"),
    active: true,
    last_verified_at: new Date().toISOString(),
  };

  let venueId = sourceRecord.found
    ? sourceRecord.canonicalVenueId ?? null
    : null;

  if (venueId) {
    const { error } = await supabase.from("venues").update(venueRow).eq("id", venueId);
    if (error) throw new Error(`Venue update: ${error.message}`);
  } else {
    const { data, error } = await supabase
      .from("venues")
      .insert(venueRow)
      .select("id")
      .single();
    if (error) throw new Error(`Venue insert: ${error.message}`);
    venueId = data.id as string;
  }

  const venueHash = await sha256(venue);
  const venueNow = new Date().toISOString();
  await callPrivateBridge(supabase, "upsert_source_record", {
    sourceId,
    entityKind: "venue",
    externalId,
    sourceUrl: getString(venue, "url"),
    payloadHash: venueHash,
    rawPayload: venue,
    parsedPayload: venueRow,
    processingStatus: "published",
    canonicalVenueId: venueId,
    lastSeenAt: venueNow,
    fetchedAt: venueNow,
  });

  return venueId;
}

async function findOrCreateOrganizer(
  supabase: ReturnType<typeof createClient>,
  promoter: JsonObject | null,
) {
  const name = getString(promoter, "name");
  if (!name) return null;

  const normalizedName = normalizeText(name);
  const { data: existing } = await supabase
    .from("organizers")
    .select("id")
    .eq("normalized_name", normalizedName)
    .limit(1)
    .maybeSingle();

  if (existing?.id) return existing.id as string;

  const { data, error } = await supabase
    .from("organizers")
    .insert({ name, active: true })
    .select("id")
    .single();
  if (error) throw new Error(`Organizer insert: ${error.message}`);
  return data.id as string;
}

async function upsertEvent(
  supabase: ReturnType<typeof createClient>,
  sourceId: string,
  ingestionRunId: string,
  event: JsonObject,
) {
  const externalId = getString(event, "id");
  const title = getString(event, "name");
  if (!externalId || !title) return { outcome: "skipped" as const };

  const embedded = getObject(event["_embedded"]);
  const venue = getObject(getArray(embedded?.["venues"])[0]);
  const venueId = await findOrCreateVenue(supabase, sourceId, venue);
  const promoter = getObject(event["promoter"]) ?? getObject(getArray(event["promoters"])[0]);
  const organizerId = await findOrCreateOrganizer(supabase, promoter);

  const dates = getObject(event["dates"]);
  const start = getObject(dates?.["start"]);
  const end = getObject(dates?.["end"]);
  const status = getObject(dates?.["status"]);
  const startAt = getString(start, "dateTime") ??
    combineLocalDateTime(getString(start, "localDate"), getString(start, "localTime"));
  const endAt = getString(end, "dateTime");
  const allDay = !getString(start, "dateTime") && Boolean(getString(start, "localDate"));
  const statusCode = getString(status, "code");
  const classification = classificationInfo(event);
  const priceRanges = getArray(event["priceRanges"])
    .map(getObject)
    .filter((item): item is JsonObject => Boolean(item));
  const minimumPrice = priceRanges
    .map((range) => getNumber(range, "min"))
    .filter((value): value is number => value !== null)
    .sort((a, b) => a - b)[0] ?? null;

  const summary = compactText(
    getString(event, "info"),
    getString(event, "pleaseNote"),
    classification.label,
  );

  const now = new Date().toISOString();
  const experienceRow = {
    kind: "event",
    title,
    summary,
    description: summary,
    language_code: (getString(event, "locale") ?? "sk").split("-")[0],
    venue_id: venueId,
    organizer_id: organizerId,
    official_url: getString(event, "url"),
    primary_ticket_url: getString(event, "url"),
    hero_image_url: chooseImage(event["images"]),
    free_entry: minimumPrice === 0,
    family_score: classification.family ? 92 : 45,
    quality_score: qualityScore(event, venue, startAt),
    publication_status: startAt && venueId ? "published" : "review",
    lifecycle_status: mapLifecycleStatus(statusCode),
    source_freshness_at: now,
    last_verified_at: now,
    last_seen_at: now,
    active: statusCode?.toLowerCase() !== "canceled",
  };

  const { data: link } = await supabase
    .from("experience_sources")
    .select("experience_id")
    .eq("source_id", sourceId)
    .eq("external_id", externalId)
    .maybeSingle();

  let experienceId = link?.experience_id as string | undefined;
  let outcome: "inserted" | "updated" = "updated";

  if (experienceId) {
    const { error } = await supabase.from("experiences").update(experienceRow).eq("id", experienceId);
    if (error) throw new Error(`Experience update: ${error.message}`);
  } else {
    const { data, error } = await supabase
      .from("experiences")
      .insert(experienceRow)
      .select("id")
      .single();
    if (error) throw new Error(`Experience insert: ${error.message}`);
    experienceId = data.id as string;
    outcome = "inserted";
  }

  const { error: sourceLinkError } = await supabase
    .from("experience_sources")
    .upsert({
      experience_id: experienceId,
      source_id: sourceId,
      external_id: externalId,
      source_url: getString(event, "url"),
      is_primary: true,
      is_official: true,
      last_seen_at: now,
      last_verified_at: now,
    }, { onConflict: "source_id,external_id" });
  if (sourceLinkError) throw new Error(`Experience source: ${sourceLinkError.message}`);

  await supabase
    .from("experience_categories")
    .update({ is_primary: false })
    .eq("experience_id", experienceId)
    .eq("is_primary", true);

  const { error: categoryError } = await supabase
    .from("experience_categories")
    .upsert({
      experience_id: experienceId,
      category_code: classification.categoryCode,
      is_primary: true,
      confidence: classification.family ? 0.9 : 0.7,
    }, { onConflict: "experience_id,category_code" });
  if (categoryError) throw new Error(`Category: ${categoryError.message}`);

  let occurrenceId: string | null = null;
  if (startAt) {
    const occurrenceKey = `ticketmaster:${externalId}:${startAt}`;
    const sales = getObject(event["sales"]);
    const publicSales = getObject(sales?.["public"]);
    const { data, error } = await supabase
      .from("experience_occurrences")
      .upsert({
        experience_id: experienceId,
        starts_at: startAt,
        ends_at: endAt,
        timezone: getString(dates, "timezone") ?? getString(venue, "timezone") ?? "Europe/Bratislava",
        all_day: allDay,
        status: mapOccurrenceStatus(statusCode),
        sales_start_at: getString(publicSales, "startDateTime"),
        sales_end_at: getString(publicSales, "endDateTime"),
        occurrence_key: occurrenceKey,
        active: statusCode?.toLowerCase() !== "canceled",
      }, { onConflict: "experience_id,occurrence_key" })
      .select("id")
      .single();
    if (error) throw new Error(`Occurrence: ${error.message}`);
    occurrenceId = data.id as string;
  }

  const { error: deactivateError } = await supabase
    .from("ticket_offers")
    .update({ active: false, updated_at: now })
    .eq("experience_id", experienceId)
    .eq("source_id", sourceId);
  if (deactivateError) throw new Error(`Offer deactivate: ${deactivateError.message}`);

  for (let index = 0; index < priceRanges.length; index += 1) {
    const range = priceRanges[index];
    const currency = (getString(range, "currency") ?? "EUR").toUpperCase().slice(0, 3);
    const min = getNumber(range, "min");
    const max = getNumber(range, "max") ?? min;
    const offerType = getString(range, "type") ?? "standard";
    const { error } = await supabase
      .from("ticket_offers")
      .upsert({
        experience_id: experienceId,
        occurrence_id: occurrenceId,
        source_id: sourceId,
        external_offer_id: `${externalId}:${offerType}:${index}`,
        offer_name: offerType === "standard" ? "Štandardné vstupné" : offerType,
        audience_type: "general",
        price_min: min,
        price_max: max,
        currency,
        free_entry: min === 0,
        fees_included: null,
        availability: mapAvailability(statusCode),
        purchase_url: getString(event, "url"),
        source_url: getString(event, "url"),
        is_official: true,
        confidence: 0.98,
        valid_from: getString(getObject(getObject(event["sales"])?.["public"]), "startDateTime"),
        valid_until: getString(getObject(getObject(event["sales"])?.["public"]), "endDateTime"),
        checked_at: now,
        active: statusCode?.toLowerCase() === "onsale",
      }, { onConflict: "source_id,external_offer_id" });
    if (error) throw new Error(`Offer: ${error.message}`);
  }

  const payloadHash = await sha256(event);
  await callPrivateBridge(supabase, "upsert_source_record", {
    sourceId,
    ingestionRunId,
    entityKind: "experience",
    externalId,
    sourceUrl: getString(event, "url"),
    payloadHash,
    rawPayload: event,
    parsedPayload: experienceRow,
    processingStatus: "published",
    canonicalExperienceId: experienceId,
    canonicalOccurrenceId: occurrenceId,
    lastSeenAt: now,
    fetchedAt: now,
  });

  return { outcome, experienceId };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Použi POST požiadavku." }, 405);
  }

  const expectedSyncToken = Deno.env.get("CATALOG_SYNC_TOKEN");
  const receivedSyncToken = req.headers.get("x-sync-token");
  if (!expectedSyncToken || receivedSyncToken !== expectedSyncToken) {
    return jsonResponse({ error: "Neplatné oprávnenie synchronizácie." }, 401);
  }

  const ticketmasterApiKey = Deno.env.get("TICKETMASTER_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseSecretKey = readSupabaseSecretKey();

  if (!ticketmasterApiKey || !supabaseUrl || !supabaseSecretKey) {
    return jsonResponse({
      error: "Chýba TICKETMASTER_API_KEY alebo serverový Supabase kľúč.",
    }, 500);
  }

  let requestBody: SyncRequest;
  try {
    requestBody = await req.json();
  } catch {
    return jsonResponse({ error: "Telo požiadavky nie je platný JSON." }, 400);
  }

  const now = new Date();
  const action: SyncAction = requestBody.action === "sync" ? "sync" : "preview";
  const countries = [...new Set((requestBody.countryCodes ?? ["SK", "CZ"])
    .map((code) => code.toUpperCase())
    .filter((code) => allowedCountries.has(code)))];

  if (countries.length === 0) {
    return jsonResponse({ error: "Povolené krajiny sú iba SK a CZ." }, 400);
  }

  const options = {
    startDateTime: toTicketmasterDateTime(
      requestBody.startDateTime ?? null,
      now,
    ),
    endDateTime: toTicketmasterDateTime(
      requestBody.endDateTime ?? null,
      addDays(now, 180),
    ),
    pageSize: clamp(Math.round(requestBody.pageSize ?? (action === "preview" ? 20 : 100)), 1, 100),
    maxPagesPerCountry: clamp(
      Math.round(requestBody.maxPagesPerCountry ?? (action === "preview" ? 1 : 3)),
      1,
      10,
    ),
    keyword: requestBody.keyword,
    classificationName: requestBody.classificationName,
  };

  const supabase = createClient(supabaseUrl, supabaseSecretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: source, error: sourceError } = await supabase
    .from("sources")
    .select("id")
    .eq("code", "ticketmaster")
    .single();
  if (sourceError || !source) {
    return jsonResponse({ error: `Zdroj Ticketmaster: ${sourceError?.message ?? "nenájdený"}` }, 500);
  }

  let connector: { found: boolean; id?: string; sourceId?: string };
  try {
    connector = await callPrivateBridge(supabase, "get_connector", {
      connectorKey: "ticketmaster_discovery",
    });
  } catch (error) {
    return jsonResponse({
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }

  if (!connector.found || !connector.id) {
    return jsonResponse({ error: "Konektor Ticketmaster nebol nájdený." }, 500);
  }

  const stats: SyncStats = {
    fetched: 0,
    inserted: 0,
    updated: 0,
    skipped: 0,
    errors: 0,
    countries: {},
    errorMessages: [],
  };

  let ingestionRunId: string | null = null;
  if (action === "sync") {
    try {
      const run = await callPrivateBridge<{ id: string }>(
        supabase,
        "start_run",
        {
          connectorId: connector.id,
          triggerType: "manual",
          stats: { countries, options },
        },
      );
      ingestionRunId = run.id;
    } catch (error) {
      return jsonResponse({
        error: error instanceof Error ? error.message : String(error),
      }, 500);
    }
  }

  const previewEvents: unknown[] = [];

  try {
    for (const countryCode of countries) {
      stats.countries[countryCode] = {
        pagesFetched: 0,
        totalElements: 0,
        eventsFetched: 0,
      };

      for (let page = 0; page < options.maxPagesPerCountry; page += 1) {
        const data = await fetchTicketmasterPage(
          ticketmasterApiKey,
          countryCode,
          page,
          options,
        );
        const embedded = getObject(data["_embedded"]);
        const events = getArray(embedded?.["events"])
          .map(getObject)
          .filter((item): item is JsonObject => Boolean(item));
        const pageInfo = getObject(data["page"]);
        const totalPages = getNumber(pageInfo, "totalPages") ?? 0;
        const totalElements = getNumber(pageInfo, "totalElements") ?? events.length;

        stats.countries[countryCode].pagesFetched += 1;
        stats.countries[countryCode].totalElements = totalElements;
        stats.countries[countryCode].eventsFetched += events.length;
        stats.fetched += events.length;

        if (action === "preview") {
          for (const event of events.slice(0, 10 - previewEvents.length)) {
            const embeddedEvent = getObject(event["_embedded"]);
            const venue = getObject(getArray(embeddedEvent?.["venues"])[0]);
            const dates = getObject(event["dates"]);
            const start = getObject(dates?.["start"]);
            previewEvents.push({
              id: getString(event, "id"),
              name: getString(event, "name"),
              countryCode,
              city: getString(getObject(venue?.["city"]), "name"),
              venue: getString(venue, "name"),
              startDateTime: getString(start, "dateTime") ?? getString(start, "localDate"),
              url: getString(event, "url"),
              priceRanges: event["priceRanges"] ?? [],
            });
          }
        } else {
          for (const event of events) {
            try {
              const result = await upsertEvent(
                supabase,
                source.id as string,
                ingestionRunId as string,
                event,
              );
              if (result.outcome === "inserted") stats.inserted += 1;
              if (result.outcome === "updated") stats.updated += 1;
              if (result.outcome === "skipped") stats.skipped += 1;
            } catch (error) {
              stats.errors += 1;
              const message = error instanceof Error ? error.message : String(error);
              if (stats.errorMessages.length < 20) stats.errorMessages.push(message);
              console.error("Ticketmaster event sync error:", message);
            }
          }
        }

        if (events.length === 0 || page + 1 >= totalPages) break;
      }
    }

    if (action === "sync" && ingestionRunId) {
      const completedStatus = stats.errors === 0 ? "completed" : "partial";
      const errorSummary = stats.errorMessages.join("\n") || null;

      await callPrivateBridge(supabase, "finish_run", {
        runId: ingestionRunId,
        status: completedStatus,
        fetchedCount: stats.fetched,
        insertedCount: stats.inserted,
        updatedCount: stats.updated,
        skippedCount: stats.skipped,
        errorCount: stats.errors,
        stats,
        errorSummary,
      });

      await callPrivateBridge(supabase, "update_connector", {
        connectorId: connector.id,
        success: true,
        errorMessage: errorSummary,
      });
    }

    return jsonResponse({
      action,
      range: {
        startDateTime: options.startDateTime,
        endDateTime: options.endDateTime,
      },
      stats,
      preview: action === "preview" ? previewEvents : undefined,
      note: action === "preview"
        ? "Preview nič nezapísal do katalógu."
        : "Synchronizácia zapísala udalosti do katalógu V2.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    if (action === "sync" && ingestionRunId) {
      await callPrivateBridge(supabase, "finish_run", {
        runId: ingestionRunId,
        status: "failed",
        fetchedCount: stats.fetched,
        insertedCount: stats.inserted,
        updatedCount: stats.updated,
        skippedCount: stats.skipped,
        errorCount: stats.errors + 1,
        stats,
        errorSummary: message,
      });

      await callPrivateBridge(supabase, "update_connector", {
        connectorId: connector.id,
        success: false,
        errorMessage: message,
      });
    }

    console.error("ticketmaster-sync fatal:", message);
    return jsonResponse({ error: message, stats }, 500);
  }
});