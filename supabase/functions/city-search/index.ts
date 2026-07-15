import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type RequestBody = {
  input?: string;
};

type GooglePrediction = {
  placeId?: string;
  text?: {
    text?: string;
  };
  structuredFormat?: {
    mainText?: {
      text?: string;
    };
    secondaryText?: {
      text?: string;
    };
  };
  types?: string[];
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const allowedPlaceTypes = new Set([
  "locality",
  "postal_town",
  "sublocality",
  "sublocality_level_1",
  "administrative_area_level_2",
  "administrative_area_level_3",
  "administrative_area_level_4",
]);

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders,
  });
}

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", {
        headers: corsHeaders,
      });
    }

    if (req.method !== "POST") {
      return jsonResponse(
        { error: "Povolená je iba POST požiadavka." },
        405,
      );
    }

    const googleApiKey =
      Deno.env.get("GOOGLE_MAPS_API_KEY");

    if (!googleApiKey) {
      return jsonResponse(
        {
          error:
            "GOOGLE_MAPS_API_KEY nie je uložený v Supabase Secrets.",
        },
        500,
      );
    }

    let body: RequestBody;

    try {
      body = await req.json();
    } catch {
      return jsonResponse(
        { error: "Telo požiadavky nie je platný JSON." },
        400,
      );
    }

    const input = body.input?.trim() ?? "";

    if (input.length < 2) {
      return jsonResponse({
        suggestions: [],
      });
    }

    const googleResponse = await fetch(
      "https://places.googleapis.com/v1/places:autocomplete",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": googleApiKey,
          "X-Goog-FieldMask": [
            "suggestions.placePrediction.placeId",
            "suggestions.placePrediction.text",
            "suggestions.placePrediction.structuredFormat",
            "suggestions.placePrediction.types",
          ].join(","),
        },
        body: JSON.stringify({
          input,
          includedRegionCodes: ["sk", "cz"],
          languageCode: "sk",
        }),
      },
    );

    const googleData = await googleResponse.json();

    if (!googleResponse.ok) {
      console.error("Google Places error:", googleData);

      return jsonResponse(
        {
          error:
            googleData?.error?.message ??
            "Google nedokázal vyhľadať miesto.",
          googleStatus: googleResponse.status,
        },
        googleResponse.status,
      );
    }

    const suggestions = (
      googleData.suggestions ?? []
    )
      .map(
        (item: {
          placePrediction?: GooglePrediction;
        }) => {
          const prediction = item.placePrediction;

          if (!prediction?.placeId) {
            return null;
          }

          const types = prediction.types ?? [];

          const isCityOrVillage =
            types.length === 0 ||
            types.some((type) =>
              allowedPlaceTypes.has(type),
            );

          if (!isCityOrVillage) {
            return null;
          }

          return {
            placeId: prediction.placeId,
            name:
              prediction.structuredFormat?.mainText
                ?.text ??
              prediction.text?.text ??
              "",
            area:
              prediction.structuredFormat
                ?.secondaryText?.text ?? "",
            fullText: prediction.text?.text ?? "",
            types,
          };
        },
      )
      .filter(Boolean);

    return jsonResponse({
      suggestions,
    });
  } catch (error) {
    console.error("city-search error:", error);

    return jsonResponse(
      {
        error:
          error instanceof Error
            ? error.message
            : "Neznáma chyba servera.",
      },
      500,
    );
  }
});