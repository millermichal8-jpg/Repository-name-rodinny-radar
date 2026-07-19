import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.0";

type JsonObject = Record<string, unknown>;

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

function asString(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function asNumber(value: unknown, fallback: number) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function stringArray(value: unknown) {
  if (!Array.isArray(value)) return null;
  const items = value.filter((item): item is string =>
    typeof item === "string" && item.trim().length > 0
  ).map((item) => item.trim());
  return items.length > 0 ? items : null;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Použi POST." }, 405);

  try {
    const expectedToken = Deno.env.get("CATALOG_SYNC_TOKEN");
    const suppliedToken = request.headers.get("X-Sync-Token");

    if (!expectedToken || suppliedToken !== expectedToken) {
      return jsonResponse({ error: "Neplatné oprávnenie Event Review." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Chýbajú Supabase serverové premenné.");
    }

    const rawBody = await request.json().catch(() => ({}));
    const body = isObject(rawBody) ? rawBody : {};
    const action = (asString(body.action) ?? "queue").toLowerCase();

    const supported = new Set([
      "queue",
      "stats",
      "audit",
      "approve",
      "publish",
      "reject",
      "restore",
      "batch-publish",
    ]);

    if (!supported.has(action)) {
      return jsonResponse({
        error:
          "action musí byť queue, stats, audit, approve, publish, reject, restore alebo batch-publish.",
      }, 400);
    }

    const writeActions = new Set([
      "approve",
      "publish",
      "reject",
      "restore",
      "batch-publish",
    ]);

    if (writeActions.has(action) && body.confirmWrite !== true) {
      return jsonResponse({
        error: "Zápis vyžaduje confirmWrite: true.",
      }, 400);
    }

    if (["approve", "publish", "reject", "restore"].includes(action)) {
      if (!asString(body.experienceId)) {
        return jsonResponse({ error: "Chýba experienceId." }, 400);
      }
    }

    const payload: JsonObject = {
      confirmWrite: body.confirmWrite === true,
      experienceId: asString(body.experienceId),
      status: asString(body.status) ?? "review",
      minQuality: Math.max(0, Math.min(100, Math.trunc(asNumber(body.minQuality, 80)))),
      limit: Math.max(1, Math.min(250, Math.trunc(asNumber(body.limit, 50)))),
      offset: Math.max(0, Math.trunc(asNumber(body.offset, 0))),
      sourceCodes: stringArray(body.sourceCodes),
      note: asString(body.note),
      actor: asString(body.actor) ?? "event-review-edge-v1",
      force: body.force === true,
    };

    const bridgeAction = action === "batch-publish" ? "batch_publish" : action;

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await supabase.rpc("catalog_event_review_bridge_v1", {
      p_action: bridgeAction,
      p_payload: payload,
    });

    if (error) throw new Error(error.message);

    return jsonResponse({
      version: "event-review-v1",
      action,
      result: data,
      note: writeActions.has(action)
        ? "Zmena bola zapísaná a auditovaná."
        : "Preview nič nezmenil.",
    });
  } catch (error) {
    console.error("event-review-v1:", error);
    return jsonResponse({
      error: error instanceof Error ? error.message : "Neznáma chyba.",
    }, 500);
  }
});
