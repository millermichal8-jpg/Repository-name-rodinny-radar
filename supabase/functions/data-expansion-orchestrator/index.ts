import { createClient } from "npm:@supabase/supabase-js@2.57.0";

type JsonObject = Record<string, unknown>;

type SourcePage = {
  code: string;
  display_name: string;
  group_code: string | null;
  priority: number | null;
  cron_enabled: boolean | null;
};

type SourceRun = {
  sourceCode: string;
  displayName: string;
  groupCode: string | null;
  ok: boolean;
  warning: boolean;
  attempts: number;
  durationMs: number;
  httpStatus: number | null;
  stats: JsonObject | null;
  error: string | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sync-token",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function asString(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function asStringArray(value: unknown) {
  if (!Array.isArray(value)) return null;
  const output = value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
  return output.length ? [...new Set(output)] : null;
}

function asInt(value: unknown, fallback: number, min: number, max: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(min, Math.min(max, Math.trunc(parsed))) : fallback;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

function sourceHasErrors(payload: JsonObject, sourceCode: string) {
  const sources = payload.sources;
  if (!sources || typeof sources !== "object" || Array.isArray(sources)) return false;
  const source = (sources as JsonObject)[sourceCode];
  if (!source || typeof source !== "object" || Array.isArray(source)) return false;
  const errors = (source as JsonObject).errors;
  return Array.isArray(errors) && errors.length > 0;
}

function extractStats(payload: JsonObject) {
  const stats = payload.stats;
  return stats && typeof stats === "object" && !Array.isArray(stats)
    ? stats as JsonObject
    : null;
}

async function invokeSource(
  functionUrl: string,
  serviceRoleKey: string,
  syncToken: string,
  source: SourcePage,
  action: "preview" | "sync",
  maxEvents: number,
  retries: number,
): Promise<SourceRun> {
  const started = Date.now();
  let lastError: string | null = null;
  let lastStatus: number | null = null;
  let attemptsUsed = 0;

  for (let attempt = 1; attempt <= retries + 1; attempt += 1) {
    attemptsUsed = attempt;
    try {
      const response = await fetchWithTimeout(functionUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
          "X-Sync-Token": syncToken,
        },
        body: JSON.stringify({
          action,
          sourceCodes: [source.code],
          maxEvents,
        }),
      }, 65_000);

      lastStatus = response.status;
      const text = await response.text();
      let payload: JsonObject = {};
      try {
        payload = text ? JSON.parse(text) as JsonObject : {};
      } catch {
        payload = { rawResponse: text.slice(0, 2000) };
      }

      if (response.ok) {
        const warning = sourceHasErrors(payload, source.code);
        return {
          sourceCode: source.code,
          displayName: source.display_name,
          groupCode: source.group_code,
          ok: !warning,
          warning,
          attempts: attempt,
          durationMs: Date.now() - started,
          httpStatus: response.status,
          stats: extractStats(payload),
          error: warning ? "Zdroj odpovedal, ale parser zaznamenal chybu." : null,
        };
      }

      lastError = asString(payload.error) ?? `HTTP ${response.status}`;
      const temporary = response.status === 408 || response.status === 429 || response.status >= 500;
      if (!temporary || attempt > retries) break;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      if (attempt > retries) break;
    }

    await sleep(750 * attempt);
  }

  return {
    sourceCode: source.code,
    displayName: source.display_name,
    groupCode: source.group_code,
    ok: false,
    warning: false,
    attempts: attemptsUsed,
    durationMs: Date.now() - started,
    httpStatus: lastStatus,
    stats: null,
    error: lastError ?? "Neznáma chyba konektora.",
  };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Použi POST." }, 405);

  try {
    const syncToken = Deno.env.get("CATALOG_SYNC_TOKEN");
    const suppliedToken = request.headers.get("X-Sync-Token");
    if (!syncToken || suppliedToken !== syncToken) {
      return jsonResponse({ error: "Neplatné oprávnenie synchronizácie." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Chýbajú Supabase serverové premenné.");
    }

    const body = await request.json().catch(() => ({})) as JsonObject;
    const action = (asString(body.action) ?? "preview") as "preview" | "sync";
    if (action !== "preview" && action !== "sync") {
      return jsonResponse({ error: "action musí byť preview alebo sync." }, 400);
    }
    if (action === "sync" && body.confirmWrite !== true) {
      return jsonResponse({ error: "Ostrý sync vyžaduje confirmWrite: true." }, 400);
    }

    const sourceCodes = asStringArray(body.sourceCodes);
    const sourceGroup = asString(body.sourceGroup);
    if (!sourceCodes && !sourceGroup) {
      return jsonResponse({
        error: "Zadaj sourceGroup alebo sourceCodes. Orchestrátor zámerne nespúšťa všetky zdroje naraz.",
      }, 400);
    }

    const maxSources = asInt(body.maxSources, 5, 1, 8);
    const sourceOffset = asInt(body.sourceOffset, 0, 0, 500);
    const maxEventsPerSource = asInt(body.maxEventsPerSource, 80, 1, 150);
    const retries = asInt(body.retries, 1, 0, 3);
    const cronEnabledOnly = body.cronEnabledOnly === true;

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await supabase.rpc("catalog_list_source_pages_v2", {
      p_codes: sourceCodes,
      p_group_code: sourceGroup,
      p_include_disabled: false,
    });
    if (error) throw new Error(`Načítanie registra zdrojov: ${error.message}`);

    const allSources = (data ?? []) as SourcePage[];
    const eligible = cronEnabledOnly
      ? allSources.filter((source) => source.cron_enabled === true)
      : allSources;
    const selected = eligible.slice(sourceOffset, sourceOffset + maxSources);
    if (!selected.length) {
      return jsonResponse({
        action,
        version: "data-expansion-orchestrator-v1",
        sourceGroup,
        message: "Pre zadaný výber sa nenašli aktívne zdroje.",
        runs: [],
      });
    }

    const functionUrl = `${supabaseUrl.replace(/\/$/, "")}/functions/v1/municipal-event-sync`;
    const startedAt = new Date().toISOString();
    const batchStarted = Date.now();
    const runs: SourceRun[] = [];

    // Zámerne sekvenčne: šetrí cudzie weby, kvóty aj pamäť Edge Function.
    for (const source of selected) {
      runs.push(await invokeSource(
        functionUrl,
        serviceRoleKey,
        syncToken,
        source,
        action,
        maxEventsPerSource,
        retries,
      ));
    }

    const ok = runs.filter((run) => run.ok).length;
    const warnings = runs.filter((run) => run.warning).length;
    const failed = runs.length - ok - warnings;

    return jsonResponse({
      action,
      version: "data-expansion-orchestrator-v1",
      startedAt,
      finishedAt: new Date().toISOString(),
      durationMs: Date.now() - batchStarted,
      sourceGroup,
      requestedSourceCodes: sourceCodes,
      selectedSourceCount: selected.length,
      sourceOffset,
      nextSourceOffset: sourceOffset + selected.length,
      remainingSourceCount: Math.max(0, eligible.length - sourceOffset - selected.length),
      limits: { maxSources, maxEventsPerSource, retries, cronEnabledOnly },
      summary: { ok, warnings, failed },
      runs,
      note: action === "preview"
        ? "Preview nič nezapísal. Ďalšiu dávku spusti až po kontrole reportu."
        : "Ostrý sync bol potvrdený a spracovaný po jednom zdroji.",
    }, failed > 0 ? 207 : 200);
  } catch (error) {
    console.error("data-expansion-orchestrator-v1:", error);
    return jsonResponse({
      error: error instanceof Error ? error.message : "Neznáma chyba.",
    }, 500);
  }
});
