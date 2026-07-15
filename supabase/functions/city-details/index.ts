import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type RequestBody = {
  placeId?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders,
  });
}

function findAddressPart(
  components: Array<{
    longText?: string;
    shortText?: string;
    types?: string[];
  }> = [],
  wantedTypes: string[],
  short = false,
) {
  const item = components.find((component) =>
    component.types?.some((type) =>
      wantedTypes.includes(type),
    ),
  );

  if (!item) {
    return null;
  }

  return short
    ? item.shortText ?? item.longText ?? null
    : item.longText ?? item.shortText ?? null;
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
        { error: "Chýba Google API kľúč." },
        500,
      );
    }

    const body = (await req.json()) as RequestBody;
    const placeId = body.placeId?.trim();

    if (!placeId) {
      return jsonResponse(
        { error: "Chýba placeId mesta." },
        400,
      );
    }

    const url =
      `https://places.googleapis.com/v1/places/` +
      `${encodeURIComponent(placeId)}?languageCode=sk`;

    const googleResponse = await fetch(url, {
      headers: {
        "X-Goog-Api-Key": googleApiKey,
        "X-Goog-FieldMask": [
          "id",
          "displayName",
          "formattedAddress",
          "location",
          "addressComponents",
          "googleMapsUri",
        ].join(","),
      },
    });

    const place = await googleResponse.json();

    if (!googleResponse.ok) {
      return jsonResponse(
        {
          error:
            place?.error?.message ??
            "Nepodarilo sa načítať údaje mesta.",
        },
        googleResponse.status,
      );
    }

    return jsonResponse({
      city: {
        placeId: place.id,
        name: place.displayName?.text ?? "",
        formattedAddress:
          place.formattedAddress ?? "",
        latitude: place.location?.latitude,
        longitude: place.location?.longitude,
        countryCode: findAddressPart(
          place.addressComponents,
          ["country"],
          true,
        ),
        country: findAddressPart(
          place.addressComponents,
          ["country"],
        ),
        region: findAddressPart(
          place.addressComponents,
          ["administrative_area_level_1"],
        ),
        googleMapsUrl: place.googleMapsUri ?? null,
      },
    });
  } catch (error) {
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