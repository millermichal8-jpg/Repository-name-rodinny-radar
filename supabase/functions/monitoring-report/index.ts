import { createClient } from "npm:@supabase/supabase-js@2.57.0";

type JsonObject = Record<string, unknown>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sync-token",
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

function asString(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Použi POST." }, 405);
  }

  try {
    const configuredToken = Deno.env.get("CATALOG_SYNC_TOKEN");
    const suppliedToken = request.headers.get("X-Sync-Token");

    if (!configuredToken || suppliedToken !== configuredToken) {
      return jsonResponse({ error: "Neplatné oprávnenie monitoringu." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Chýbajú Supabase serverové premenné.");
    }

    const body = await request.json().catch(() => ({})) as JsonObject;
    const action = asString(body.action) ?? "preview";
    const includeCron = body.includeCron !== false;

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (action === "preview" || action === "check") {
      if (action === "check" && body.confirmWrite !== true) {
        return jsonResponse({
          error: "Zápis incidentov vyžaduje confirmWrite: true.",
        }, 400);
      }

      const { data, error } = await supabase.rpc("catalog_monitoring_evaluate_v1", {
        p_record: action === "check",
        p_include_cron: includeCron,
        p_now: new Date().toISOString(),
      });

      if (error) {
        throw new Error(`Vyhodnotenie monitoringu: ${error.message}`);
      }

      return jsonResponse({
        action,
        version: "monitoring-report-v1",
        result: data,
      });
    }

    if (action === "incidents") {
      const { data, error } = await supabase.rpc(
        "catalog_monitoring_open_incidents_v1",
      );

      if (error) {
        throw new Error(`Načítanie incidentov: ${error.message}`);
      }

      return jsonResponse({
        action,
        version: "monitoring-report-v1",
        incidents: data ?? [],
      });
    }

    if (action === "acknowledge") {
      if (body.confirmWrite !== true) {
        return jsonResponse({
          error: "Potvrdenie incidentu vyžaduje confirmWrite: true.",
        }, 400);
      }

      const incidentId = asString(body.incidentId);
      if (!incidentId) {
        return jsonResponse({ error: "Chýba incidentId." }, 400);
      }

      const { data, error } = await supabase.rpc(
        "catalog_monitoring_acknowledge_incident_v1",
        {
          p_incident_id: incidentId,
          p_note: asString(body.note),
        },
      );

      if (error) {
        throw new Error(`Potvrdenie incidentu: ${error.message}`);
      }

      return jsonResponse({
        action,
        version: "monitoring-report-v1",
        result: data,
      });
    }

    return jsonResponse({
      error: "action musí byť preview, check, incidents alebo acknowledge.",
    }, 400);
  } catch (error) {
    console.error("monitoring-report-v1:", error);
    return jsonResponse({
      error: error instanceof Error ? error.message : "Neznáma chyba.",
    }, 500);
  }
});
