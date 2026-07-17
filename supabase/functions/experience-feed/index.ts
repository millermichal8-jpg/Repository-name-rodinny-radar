import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

type FeedRequest = {
  latitude?: number;
  longitude?: number;
  radiusKm?: number;
  minChildAge?: number;
  maxChildAge?: number;
  freeOnly?: boolean;
  limit?: number;
};

type SearchRow = {
  id: string;
  kind: 'attraction' | 'event';
  title: string;
  summary: string | null;
  hero_image_url: string | null;
  venue_name: string | null;
  city: string | null;
  region: string | null;
  country_code: string | null;
  latitude: number | null;
  longitude: number | null;
  distance_km: number | string | null;
  primary_category_code: string | null;
  primary_category_name: string | null;
  primary_category_emoji: string | null;
  next_occurrence_id: string | null;
  next_starts_at: string | null;
  next_ends_at: string | null;
  next_all_day: boolean | null;
  price_min: number | string | null;
  price_max: number | string | null;
  currency: string | null;
  offer_name: string | null;
  purchase_url: string | null;
  free_entry: boolean | null;
  family_score: number;
  quality_score: number;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': status === 200
        ? 'public, max-age=120, stale-while-revalidate=300'
        : 'no-store',
    },
  });
}

function finiteNumber(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Použi POST.' }, 405);
  }

  try {
    const input = await request.json().catch(() => ({})) as FeedRequest;
    const latitude = finiteNumber(input.latitude);
    const longitude = finiteNumber(input.longitude);

    if (
      latitude === null ||
      longitude === null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return jsonResponse({ error: 'Chýbajú platné GPS súradnice.' }, 400);
    }

    const radiusKm = clamp(finiteNumber(input.radiusKm) ?? 50, 1, 500);
    const limit = Math.round(clamp(finiteNumber(input.limit) ?? 30, 1, 60));
    const minChildAge = finiteNumber(input.minChildAge);
    const maxChildAge = finiteNumber(input.maxChildAge);

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Chýba serverová konfigurácia Supabase.');
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const from = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const to = new Date(
      Date.now() + 180 * 24 * 60 * 60 * 1000,
    ).toISOString();

    const { data, error } = await supabase.rpc('search_experiences', {
      p_latitude: latitude,
      p_longitude: longitude,
      p_radius_km: radiusKm,
      p_from: from,
      p_to: to,
      p_kinds: ['event'],
      p_category_codes: null,
      p_min_child_age: minChildAge === null
        ? null
        : Math.round(clamp(minChildAge, 0, 17)),
      p_max_child_age: maxChildAge === null
        ? null
        : Math.round(clamp(maxChildAge, 0, 17)),
      p_free_only: Boolean(input.freeOnly),
      p_limit: limit,
      p_offset: 0,
    });

    if (error) {
      throw new Error(`Načítanie podujatí zlyhalo: ${error.message}`);
    }

    const rows = (data ?? []) as SearchRow[];
    const ids = rows.map((row) => row.id);
    const urlById = new Map<string, string | null>();

    if (ids.length > 0) {
      const { data: urlRows, error: urlError } = await supabase
        .from('experiences')
        .select('id,official_url,primary_ticket_url')
        .in('id', ids);

      if (urlError) {
        throw new Error(`Načítanie odkazov zlyhalo: ${urlError.message}`);
      }

      for (const item of urlRows ?? []) {
        urlById.set(
          item.id,
          item.primary_ticket_url ?? item.official_url ?? null,
        );
      }
    }

    const events = rows.map((row) => ({
      id: row.id,
      title: row.title,
      summary: row.summary,
      imageUrl: row.hero_image_url,
      venueName: row.venue_name,
      city: row.city,
      region: row.region,
      countryCode: row.country_code,
      latitude: finiteNumber(row.latitude),
      longitude: finiteNumber(row.longitude),
      distanceKm: finiteNumber(row.distance_km),
      categoryCode: row.primary_category_code,
      categoryName: row.primary_category_name,
      emoji: row.primary_category_emoji ?? '🎪',
      startsAt: row.next_starts_at,
      endsAt: row.next_ends_at,
      allDay: Boolean(row.next_all_day),
      priceMin: finiteNumber(row.price_min),
      priceMax: finiteNumber(row.price_max),
      currency: row.currency ?? 'EUR',
      offerName: row.offer_name,
      purchaseUrl: row.purchase_url ?? urlById.get(row.id) ?? null,
      freeEntry: Boolean(row.free_entry) || finiteNumber(row.price_min) === 0,
      familyScore: row.family_score,
      qualityScore: row.quality_score,
    }));

    return jsonResponse({
      search: {
        latitude,
        longitude,
        radiusKm,
        resultCount: events.length,
        from,
        to,
      },
      events,
    });
  } catch (error) {
    console.error('experience-feed:', error);
    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Podujatia sa nepodarilo načítať.',
      },
      500,
    );
  }
});
