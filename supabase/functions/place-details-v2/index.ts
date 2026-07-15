import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type RequestBody = {
  placeId?: string;
};

type JsonObject = Record<string, unknown>;

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

function isObject(value: unknown): value is JsonObject {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
}

function getNestedErrorMessage(data: unknown): string | null {
  if (!isObject(data)) {
    return null;
  }

  const errorValue = data["error"];

  if (typeof errorValue === "string") {
    return errorValue;
  }

  if (isObject(errorValue)) {
    const message = errorValue["message"];

    if (typeof message === "string") {
      return message;
    }
  }

  const message = data["message"];

  return typeof message === "string" ? message : null;
}

function translatePriceLevel(priceLevel: unknown) {
  switch (priceLevel) {
    case "PRICE_LEVEL_FREE":
      return "Bezplatné";
    case "PRICE_LEVEL_INEXPENSIVE":
      return "Skôr lacné";
    case "PRICE_LEVEL_MODERATE":
      return "Stredná cenová úroveň";
    case "PRICE_LEVEL_EXPENSIVE":
      return "Skôr drahšie";
    case "PRICE_LEVEL_VERY_EXPENSIVE":
      return "Veľmi drahé";
    default:
      return null;
  }
}

function translateBusinessStatus(status: unknown) {
  switch (status) {
    case "OPERATIONAL":
      return "V prevádzke";
    case "CLOSED_TEMPORARILY":
      return "Dočasne zatvorené";
    case "CLOSED_PERMANENTLY":
      return "Trvalo zatvorené";
    case "FUTURE_OPENING":
      return "Pripravuje sa otvorenie";
    default:
      return null;
  }
}

function readString(
  object: JsonObject,
  key: string,
): string | null {
  const value = object[key];
  return typeof value === "string" ? value : null;
}

function readNumber(
  object: JsonObject,
  key: string,
): number | null {
  const value = object[key];
  return typeof value === "number" ? value : null;
}

function readBoolean(
  object: JsonObject,
  key: string,
): boolean | null {
  const value = object[key];
  return typeof value === "boolean" ? value : null;
}

function readStringArray(
  object: JsonObject,
  key: string,
): string[] {
  const value = object[key];

  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(
    (item): item is string => typeof item === "string",
  );
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

    let requestBody: RequestBody;

    try {
      requestBody = await req.json();
    } catch {
      return jsonResponse(
        { error: "Telo požiadavky nie je platný JSON." },
        400,
      );
    }

    const placeId = requestBody.placeId?.trim();

    if (!placeId) {
      return jsonResponse(
        { error: "Chýba placeId výletu." },
        400,
      );
    }

    const googleUrl =
      `https://places.googleapis.com/v1/places/` +
      `${encodeURIComponent(placeId)}?languageCode=sk`;

    const googleResponse = await fetch(googleUrl, {
      method: "GET",
      headers: {
        "X-Goog-Api-Key": googleApiKey,
        "X-Goog-FieldMask": [
          "id",
          "displayName",
          "formattedAddress",
          "googleMapsUri",
          "websiteUri",
          "nationalPhoneNumber",
          "internationalPhoneNumber",
          "rating",
          "userRatingCount",
          "priceLevel",
          "businessStatus",
          "currentOpeningHours",
          "regularOpeningHours",
        ].join(","),
      },
    });

    const rawResponse = await googleResponse.text();

    let parsedResponse: unknown = {};

    if (rawResponse.trim()) {
      try {
        parsedResponse = JSON.parse(rawResponse);
      } catch {
        console.error(
          "Google vrátil neplatný JSON:",
          rawResponse,
        );

        return jsonResponse(
          {
            error: "Google vrátil nečitateľnú odpoveď.",
            googleStatus: googleResponse.status,
          },
          502,
        );
      }
    }

    if (!googleResponse.ok) {
      console.error(
        "Google Place Details error:",
        parsedResponse,
      );

      return jsonResponse(
        {
          error:
            getNestedErrorMessage(parsedResponse) ??
            "Nepodarilo sa načítať detail výletu.",
          googleStatus: googleResponse.status,
          googleResponse: parsedResponse,
        },
        googleResponse.status,
      );
    }

    if (!isObject(parsedResponse)) {
      return jsonResponse(
        {
          error: "Google nevrátil platný objekt detailu výletu.",
        },
        502,
      );
    }

    const place = parsedResponse;

    const displayNameValue = place["displayName"];
    const displayName = isObject(displayNameValue)
      ? readString(displayNameValue, "text") ?? ""
      : "";

    const currentHoursValue =
      place["currentOpeningHours"];

    const regularHoursValue =
      place["regularOpeningHours"];

    const currentHours = isObject(currentHoursValue)
      ? currentHoursValue
      : null;

    const regularHours = isObject(regularHoursValue)
      ? regularHoursValue
      : null;

    const openingHours = currentHours
      ? readStringArray(
          currentHours,
          "weekdayDescriptions",
        )
      : regularHours
        ? readStringArray(
            regularHours,
            "weekdayDescriptions",
          )
        : [];

    const phone =
      readString(place, "nationalPhoneNumber") ??
      readString(place, "internationalPhoneNumber");

    const priceLevel = readString(place, "priceLevel");
    const businessStatus =
      readString(place, "businessStatus");

    return jsonResponse({
      place: {
        placeId: readString(place, "id") ?? placeId,
        name: displayName,
        formattedAddress:
          readString(place, "formattedAddress") ?? "",
        googleMapsUrl:
          readString(place, "googleMapsUri"),
        websiteUrl:
          readString(place, "websiteUri"),
        phone,
        rating: readNumber(place, "rating"),
        userRatingCount:
          readNumber(place, "userRatingCount") ?? 0,
        priceLevel,
        priceLabel:
          translatePriceLevel(priceLevel),
        businessStatus,
        businessStatusLabel:
          translateBusinessStatus(businessStatus),
        openNow: currentHours
          ? readBoolean(currentHours, "openNow")
          : null,
        nextOpenTime: currentHours
          ? readString(currentHours, "nextOpenTime")
          : null,
        nextCloseTime: currentHours
          ? readString(currentHours, "nextCloseTime")
          : null,
        openingHours,
      },
    });
  } catch (error) {
    console.error("place-details error:", error);

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