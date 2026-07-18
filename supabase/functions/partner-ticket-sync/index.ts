import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.0";

type JsonObject = Record<string, unknown>;
type Action = "validate" | "preview" | "sync";
type ProviderCode = "goout" | "predpredaj" | "ticketportal" | "ticketlive" | "eventim";

type ProviderConfig = {
  sourceCode: string;
  connectorKey: string;
  feedUrlEnv: string;
  feedTokenEnv: string;
  displayName: string;
};

type NormalizedPartnerEvent = {
  sourceCode: string;
  externalId: string;
  sourceUrl: string;
  purchaseUrl: string | null;
  title: string;
  summary: string | null;
  description: string | null;
  countryCode: "SK" | "CZ";
  city: string | null;
  region: string | null;
  venueName: string | null;
  address: string | null;
  imageUrl: string | null;
  startDate: string;
  endDate: string | null;
  allDay: boolean;
  freeEntry: boolean;
  priceMin: number | null;
  priceMax: number | null;
  currency: "EUR" | "CZK";
  qualityScore: number;
  raw: JsonObject;
};

type ValidationIssue = {
  index: number;
  externalId: string | null;
  severity: "warning" | "error";
  code: string;
  message: string;
};

const providers: Record<ProviderCode, ProviderConfig> = {
  goout: {
    sourceCode: "goout",
    connectorKey: "goout_partner",
    feedUrlEnv: "GOOUT_PARTNER_FEED_URL",
    feedTokenEnv: "GOOUT_PARTNER_FEED_TOKEN",
    displayName: "GoOut",
  },
  predpredaj: {
    sourceCode: "predpredaj",
    connectorKey: "predpredaj_partner",
    feedUrlEnv: "PREDPREDAJ_PARTNER_FEED_URL",
    feedTokenEnv: "PREDPREDAJ_PARTNER_FEED_TOKEN",
    displayName: "Predpredaj.sk",
  },
  ticketportal: {
    sourceCode: "ticketportal",
    connectorKey: "ticketportal_partner",
    feedUrlEnv: "TICKETPORTAL_PARTNER_FEED_URL",
    feedTokenEnv: "TICKETPORTAL_PARTNER_FEED_TOKEN",
    displayName: "Ticketportal",
  },
  ticketlive: {
    sourceCode: "ticketlive",
    connectorKey: "ticketlive_partner",
    feedUrlEnv: "TICKETLIVE_PARTNER_FEED_URL",
    feedTokenEnv: "TICKETLIVE_PARTNER_FEED_TOKEN",
    displayName: "TicketLIVE",
  },
  eventim: {
    sourceCode: "eventim",
    connectorKey: "eventim_partner",
    feedUrlEnv: "EVENTIM_PARTNER_FEED_URL",
    feedTokenEnv: "EVENTIM_PARTNER_FEED_TOKEN",
    displayName: "Eventim",
  },
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sync-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asObject(value: unknown): JsonObject | null {
  return isObject(value) ? value : null;
}

function stringValue(object: JsonObject, ...keys: string[]) {
  for (const key of keys) {
    const value = object[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return null;
}

function booleanValue(object: JsonObject, ...keys: string[]) {
  for (const key of keys) {
    const value = object[key];
    if (typeof value === "boolean") return value;
    if (typeof value === "string") {
      const normalized = value.trim().toLowerCase();
      if (normalized === "true" || normalized === "1" || normalized === "yes") return true;
      if (normalized === "false" || normalized === "0" || normalized === "no") return false;
    }
  }
  return null;
}

function numberValue(object: JsonObject, ...keys: string[]) {
  for (const key of keys) {
    const value = object[key];
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string" && value.trim()) {
      const normalized = value.replace(/\s/g, "").replace(",", ".");
      const parsed = Number(normalized);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return null;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function normalizeIsoDate(value: string | null) {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function compactText(value: string | null, maxLength: number) {
  if (!value) return null;
  const clean = value.replace(/\s+/g, " ").trim();
  return clean ? clean.slice(0, maxLength) : null;
}

function normalizeCountry(value: string | null): "SK" | "CZ" | null {
  const country = value?.trim().toUpperCase();
  return country === "SK" || country === "CZ" ? country : null;
}

function normalizeCurrency(value: string | null, country: "SK" | "CZ") {
  const currency = value?.trim().toUpperCase();
  if (currency === "EUR" || currency === "CZK") return currency;
  return country === "CZ" ? "CZK" : "EUR";
}

function calculateQuality(event: {
  title: string;
  startDate: string;
  city: string | null;
  venueName: string | null;
  sourceUrl: string;
  purchaseUrl: string | null;
  imageUrl: string | null;
  priceMin: number | null;
  freeEntry: boolean;
}) {
  let score = 25;
  if (event.title.length >= 4) score += 15;
  if (event.startDate) score += 20;
  if (event.city) score += 10;
  if (event.venueName) score += 10;
  if (event.sourceUrl) score += 5;
  if (event.purchaseUrl) score += 5;
  if (event.imageUrl) score += 5;
  if (event.priceMin !== null || event.freeEntry) score += 5;
  return clamp(score, 0, 100);
}

function extractRawEvents(payload: unknown) {
  if (Array.isArray(payload)) return payload;
  const root = asObject(payload);
  if (!root) return [];
  const candidates = [root.events, root.items, root.data, root.results];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) return candidate;
  }
  return [];
}

function normalizeEvent(
  provider: ProviderConfig,
  value: unknown,
  index: number,
): { event: NormalizedPartnerEvent | null; issues: ValidationIssue[] } {
  const issues: ValidationIssue[] = [];
  const raw = asObject(value);
  if (!raw) {
    return {
      event: null,
      issues: [{
        index,
        externalId: null,
        severity: "error",
        code: "not_object",
        message: "Položka podujatia nie je JSON objekt.",
      }],
    };
  }

  const externalId = stringValue(raw, "externalId", "external_id", "id", "eventId");
  const title = stringValue(raw, "title", "name");
  const sourceUrl = stringValue(raw, "sourceUrl", "source_url", "url", "detailUrl");
  const startDateRaw = stringValue(raw, "startDate", "start_date", "startAt", "startsAt");
  const country = normalizeCountry(stringValue(raw, "countryCode", "country_code", "country"));

  const required = [
    ["external_id", externalId, "Chýba externalId."],
    ["title", title, "Chýba title."],
    ["source_url", sourceUrl, "Chýba sourceUrl."],
    ["start_date", startDateRaw, "Chýba startDate."],
    ["country", country, "countryCode musí byť SK alebo CZ."],
  ] as const;

  for (const [code, field, message] of required) {
    if (!field) {
      issues.push({
        index,
        externalId,
        severity: "error",
        code,
        message,
      });
    }
  }

  if (issues.some((issue) => issue.severity === "error")) {
    return { event: null, issues };
  }

  const startDate = normalizeIsoDate(startDateRaw);
  if (!startDate) {
    issues.push({
      index,
      externalId,
      severity: "error",
      code: "invalid_start_date",
      message: "startDate nie je platný dátum ISO 8601.",
    });
    return { event: null, issues };
  }

  const endDateRaw = stringValue(raw, "endDate", "end_date", "endAt", "endsAt");
  let endDate = normalizeIsoDate(endDateRaw);
  if (endDateRaw && !endDate) {
    issues.push({
      index,
      externalId,
      severity: "warning",
      code: "invalid_end_date",
      message: "Neplatný endDate bol zahodený.",
    });
  }
  if (endDate && new Date(endDate).getTime() < new Date(startDate).getTime()) {
    endDate = null;
    issues.push({
      index,
      externalId,
      severity: "warning",
      code: "end_before_start",
      message: "endDate bol skorší než startDate, preto bol zahodený.",
    });
  }

  const priceMinRaw = numberValue(raw, "priceMin", "price_min", "minimumPrice");
  const priceMaxRaw = numberValue(raw, "priceMax", "price_max", "maximumPrice");
  let priceMin = priceMinRaw !== null && priceMinRaw >= 0 ? priceMinRaw : null;
  let priceMax = priceMaxRaw !== null && priceMaxRaw >= 0 ? priceMaxRaw : null;
  if (priceMin !== null && priceMax !== null && priceMax < priceMin) {
    [priceMin, priceMax] = [priceMax, priceMin];
    issues.push({
      index,
      externalId,
      severity: "warning",
      code: "price_range_swapped",
      message: "priceMin a priceMax boli prehodené do správneho poradia.",
    });
  }

  const freeEntry = booleanValue(raw, "freeEntry", "free_entry") ?? priceMin === 0;
  const purchaseUrl = stringValue(raw, "purchaseUrl", "purchase_url", "ticketUrl", "ticket_url");
  const imageUrl = stringValue(raw, "imageUrl", "image_url", "image");
  const normalizedCountry = country as "SK" | "CZ";

  const base = {
    title: title as string,
    startDate,
    city: stringValue(raw, "city"),
    venueName: stringValue(raw, "venueName", "venue_name", "venue"),
    sourceUrl: sourceUrl as string,
    purchaseUrl,
    imageUrl,
    priceMin,
    freeEntry,
  };

  const event: NormalizedPartnerEvent = {
    sourceCode: provider.sourceCode,
    externalId: externalId as string,
    sourceUrl: sourceUrl as string,
    purchaseUrl,
    title: compactText(title, 300) as string,
    summary: compactText(stringValue(raw, "summary", "subtitle"), 1000),
    description: compactText(stringValue(raw, "description", "info"), 12000),
    countryCode: normalizedCountry,
    city: compactText(base.city, 120),
    region: compactText(stringValue(raw, "region"), 160),
    venueName: compactText(base.venueName, 240),
    address: compactText(stringValue(raw, "address", "formattedAddress", "formatted_address"), 500),
    imageUrl,
    startDate,
    endDate,
    allDay: booleanValue(raw, "allDay", "all_day") ?? false,
    freeEntry,
    priceMin,
    priceMax,
    currency: normalizeCurrency(stringValue(raw, "currency"), normalizedCountry),
    qualityScore: calculateQuality(base),
    raw,
  };

  if (!event.city && !event.venueName) {
    issues.push({
      index,
      externalId,
      severity: "warning",
      code: "missing_location",
      message: "Chýba mesto aj názov miesta; záznam zostane na review.",
    });
  }

  return { event, issues };
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
  if (error) throw new Error(`Private bridge ${action}: ${error.message}`);
  return data as T;
}

async function fetchProviderFeed(provider: ProviderConfig) {
  const feedUrl = Deno.env.get(provider.feedUrlEnv)?.trim();
  if (!feedUrl) {
    throw new Error(
      `Chýba ${provider.feedUrlEnv}. Konektor čaká na partnerský feed alebo API.`,
    );
  }

  const parsedUrl = new URL(feedUrl);
  if (parsedUrl.protocol !== "https:") {
    throw new Error("Partnerský feed musí používať HTTPS.");
  }

  const token = Deno.env.get(provider.feedTokenEnv)?.trim();
  const response = await fetch(parsedUrl, {
    method: "GET",
    headers: {
      Accept: "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    signal: AbortSignal.timeout(60_000),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${provider.displayName} feed HTTP ${response.status}: ${text.slice(0, 500)}`);
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new Error(`${provider.displayName} feed nevrátil platný JSON.`);
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Použi POST." }, 405);

  try {
    const expectedToken = Deno.env.get("CATALOG_SYNC_TOKEN");
    const suppliedToken = request.headers.get("X-Sync-Token");
    if (!expectedToken || suppliedToken !== expectedToken) {
      return jsonResponse({ error: "Neplatné oprávnenie synchronizácie." }, 401);
    }

    const body = await request.json().catch(() => ({})) as JsonObject;
    const providerCode = stringValue(body, "provider") as ProviderCode | null;
    if (!providerCode || !(providerCode in providers)) {
      return jsonResponse({
        error: "provider musí byť goout, predpredaj, ticketportal, ticketlive alebo eventim.",
      }, 400);
    }

    const provider = providers[providerCode];
    const requestedAction = stringValue(body, "action") ?? "preview";
    const action: Action = requestedAction === "sync"
      ? "sync"
      : requestedAction === "validate"
      ? "validate"
      : "preview";

    if (action === "sync" && body.confirmWrite !== true) {
      return jsonResponse({ error: "Ostrý sync vyžaduje confirmWrite: true." }, 400);
    }

    const maxEvents = clamp(Math.trunc(numberValue(body, "maxEvents") ?? 100), 1, 500);
    const fixturePayload = Array.isArray(body.events) ? body.events : null;

    if (action === "sync" && fixturePayload) {
      return jsonResponse({
        error: "Ostrý sync nepovoľuje udalosti poslané v požiadavke. Musí použiť schválený partnerský feed.",
      }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Chýbajú Supabase serverové premenné.");
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const connector = await callPrivateBridge<{
      found: boolean;
      id?: string;
      sourceId?: string;
      enabled?: boolean;
    }>(supabase, "get_connector", { connectorKey: provider.connectorKey });

    if (!connector.found || !connector.id) {
      return jsonResponse({ error: `Konektor ${provider.connectorKey} nebol nájdený.` }, 500);
    }

    if (action === "sync" && connector.enabled !== true) {
      return jsonResponse({
        error: `${provider.displayName} konektor je zámerne vypnutý, kým nemáme písomné povolenie a partnerský feed.`
      }, 409);
    }

    const rawPayload = fixturePayload ?? await fetchProviderFeed(provider);
    const rawEvents = extractRawEvents(rawPayload).slice(0, maxEvents);
    const normalized: NormalizedPartnerEvent[] = [];
    const issues: ValidationIssue[] = [];

    rawEvents.forEach((item, index) => {
      const result = normalizeEvent(provider, item, index);
      issues.push(...result.issues);
      if (result.event) normalized.push(result.event);
    });

    const errors = issues.filter((issue) => issue.severity === "error");
    const warnings = issues.filter((issue) => issue.severity === "warning");

    if (action === "validate" || action === "preview") {
      return jsonResponse({
        action,
        version: "partner-ticket-sync-v1",
        provider: providerCode,
        providerName: provider.displayName,
        accessMode: fixturePayload ? "fixture" : "partner-feed",
        fetched: rawEvents.length,
        accepted: normalized.length,
        rejected: errors.length,
        warnings: warnings.length,
        issues,
        sample: normalized.slice(0, 20),
        canSync: connector.enabled === true && Boolean(Deno.env.get(provider.feedUrlEnv)),
        note: "Preview nič nezapísal. Ostrý sync je povolený až po partnerskom súhlase, zapnutí konektora a nastavení feedu.",
      });
    }

    let runId: string | null = null;
    let insertedOrUpdated = 0;
    let writeErrors = 0;
    const writeResults: Array<JsonObject> = [];

    try {
      const run = await callPrivateBridge<{ id: string }>(supabase, "start_run", {
        connectorId: connector.id,
        triggerType: "manual",
        stats: { provider: providerCode, fetched: rawEvents.length },
      });
      runId = run.id;

      for (const event of normalized) {
        try {
          const { data, error } = await supabase.rpc("catalog_ingest_web_event_v1", {
            p_event: event,
          });
          if (error) throw new Error(error.message);
          insertedOrUpdated += 1;
          writeResults.push({ externalId: event.externalId, result: data });
        } catch (error) {
          writeErrors += 1;
          writeResults.push({
            externalId: event.externalId,
            title: event.title,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }

      await callPrivateBridge(supabase, "finish_run", {
        runId,
        status: writeErrors > 0 ? "partial" : "completed",
        fetchedCount: rawEvents.length,
        insertedCount: insertedOrUpdated,
        updatedCount: 0,
        skippedCount: errors.length,
        errorCount: writeErrors,
        stats: { provider: providerCode, warnings: warnings.length },
        errorSummary: writeErrors > 0 ? `${writeErrors} chýb zápisu.` : null,
      });

      await callPrivateBridge(supabase, "update_connector", {
        connectorId: connector.id,
        success: writeErrors === 0,
        errorMessage: writeErrors > 0 ? `${writeErrors} chýb zápisu.` : null,
      });
    } catch (error) {
      if (runId) {
        await callPrivateBridge(supabase, "finish_run", {
          runId,
          status: "failed",
          fetchedCount: rawEvents.length,
          insertedCount: insertedOrUpdated,
          updatedCount: 0,
          skippedCount: errors.length,
          errorCount: writeErrors + 1,
          stats: { provider: providerCode },
          errorSummary: error instanceof Error ? error.message : String(error),
        }).catch(() => undefined);
      }
      throw error;
    }

    return jsonResponse({
      action,
      version: "partner-ticket-sync-v1",
      provider: providerCode,
      fetched: rawEvents.length,
      accepted: normalized.length,
      validationErrors: errors.length,
      validationWarnings: warnings.length,
      insertedOrUpdated,
      writeErrors,
      results: writeResults,
      note: "Záznamy boli uložené cez katalóg V2 so stavom review.",
    }, writeErrors > 0 ? 207 : 200);
  } catch (error) {
    console.error("partner-ticket-sync-v1:", error);
    return jsonResponse({
      error: error instanceof Error ? error.message : "Neznáma chyba.",
    }, 500);
  }
});
