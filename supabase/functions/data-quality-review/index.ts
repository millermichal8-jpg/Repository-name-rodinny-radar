import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.0";

type JsonObject = Record<string, unknown>;
type Action = "preview" | "refresh" | "stats" | "merge";

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

function stringValue(object: JsonObject, key: string) {
  const value = object[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function numberValue(object: JsonObject, key: string, fallback: number) {
  const value = object[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

async function bridge<T>(
  supabase: ReturnType<typeof createClient>,
  action: string,
  payload: JsonObject = {},
) {
  const { data, error } = await supabase.rpc("catalog_data_quality_bridge_v1", {
    p_action: action,
    p_payload: payload,
  });
  if (error) throw new Error(error.message);
  return data as T;
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

    const bodyValue = await request.json().catch(() => ({}));
    const body = isObject(bodyValue) ? bodyValue : {};
    const requestedAction = stringValue(body, "action") ?? "preview";
    const action: Action = requestedAction === "refresh"
      ? "refresh"
      : requestedAction === "stats"
      ? "stats"
      : requestedAction === "merge"
      ? "merge"
      : "preview";

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Chýbajú Supabase serverové premenné.");
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (action === "stats") {
      const stats = await bridge<JsonObject>(supabase, "stats");
      return jsonResponse({ version: "data-quality-review-v1", action, stats });
    }

    if (action === "merge") {
      if (body.confirmWrite !== true) {
        return jsonResponse({ error: "Spájanie vyžaduje confirmWrite: true." }, 400);
      }

      const candidateId = stringValue(body, "candidateId");
      if (!candidateId) return jsonResponse({ error: "Chýba candidateId." }, 400);

      const result = await bridge<JsonObject>(supabase, "merge_candidate", {
        candidateId,
        keepExperienceId: stringValue(body, "keepExperienceId"),
        reason: stringValue(body, "reason") ?? "Manuálne potvrdená duplicita.",
        confirmWrite: true,
      });

      return jsonResponse({ version: "data-quality-review-v1", action, result });
    }

    const refresh = await bridge<JsonObject>(supabase, "refresh_candidates", {
      daysBack: Math.max(1, Math.min(730, Math.trunc(numberValue(body, "daysBack", 180)))),
      scanLimit: Math.max(1, Math.min(10000, Math.trunc(numberValue(body, "scanLimit", 2000)))),
    });

    const candidates = await bridge<unknown[]>(supabase, "list_candidates", {
      limit: Math.max(1, Math.min(500, Math.trunc(numberValue(body, "limit", 50)))),
    });

    const stats = await bridge<JsonObject>(supabase, "stats");

    return jsonResponse({
      version: "data-quality-review-v1",
      action,
      writeMode: "candidate-table-only",
      publicExperiencesChanged: false,
      refresh,
      stats,
      candidates,
      note: "Preview obnovil iba zoznam kandidátov. Podujatia sa nespájajú bez action=merge a confirmWrite=true.",
    });
  } catch (error) {
    console.error("data-quality-review-v1:", error);
    return jsonResponse({
      error: error instanceof Error ? error.message : "Neznáma chyba.",
    }, 500);
  }
});
