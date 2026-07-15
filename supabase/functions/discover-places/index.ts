import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type RequestBody = {
  latitude?: number;
  longitude?: number;
  radiusKm?: number;
};

type AddressComponent = {
  longText?: string;
  shortText?: string;
  types?: string[];
};

type GooglePlace = {
  id?: string;
  displayName?: {
    text?: string;
  };
  formattedAddress?: string;
  addressComponents?: AddressComponent[];
  location?: {
    latitude?: number;
    longitude?: number;
  };
  primaryType?: string;
  types?: string[];
  googleMapsUri?: string;
  businessStatus?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const familyPlaceTypes = [
  "amusement_center",
  "amusement_park",
  "aquarium",
  "art_gallery",
  "art_museum",
  "botanical_garden",
  "castle",
  "city_park",
  "cultural_landmark",
  "garden",
  "hiking_area",
  "historical_landmark",
  "historical_place",
  "history_museum",
  "indoor_playground",
  "miniature_golf_course",
  "museum",
  "national_park",
  "observation_deck",
  "park",
  "picnic_ground",
  "planetarium",
  "playground",
  "tourist_attraction",
  "visitor_center",
  "water_park",
  "wildlife_park",
  "zoo",
];

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders,
  });
}

function getAddressPart(
  components: AddressComponent[] = [],
  wantedTypes: string[],
  useShortText = false,
) {
  const component = components.find((item) =>
    item.types?.some((type) => wantedTypes.includes(type)),
  );

  if (!component) {
    return null;
  }

  return useShortText
    ? component.shortText ?? component.longText ?? null
    : component.longText ?? component.shortText ?? null;
}

function toRadians(value: number) {
  return (value * Math.PI) / 180;
}

function calculateDistanceKm(
  originLatitude: number,
  originLongitude: number,
  destinationLatitude: number,
  destinationLongitude: number,
) {
  const earthRadiusKm = 6371;

  const latitudeDifference = toRadians(
    destinationLatitude - originLatitude,
  );

  const longitudeDifference = toRadians(
    destinationLongitude - originLongitude,
  );

  const originLatitudeRadians = toRadians(originLatitude);
  const destinationLatitudeRadians = toRadians(destinationLatitude);

  const haversine =
    Math.sin(latitudeDifference / 2) ** 2 +
    Math.cos(originLatitudeRadians) *
      Math.cos(destinationLatitudeRadians) *
      Math.sin(longitudeDifference / 2) ** 2;

  const centralAngle =
    2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));

  return Math.round(earthRadiusKm * centralAngle * 10) / 10;
}

function getCategory(primaryType?: string, types: string[] = []) {
  const allTypes = new Set([
    primaryType,
    ...types,
  ].filter(Boolean));

  if (
    allTypes.has("zoo") ||
    allTypes.has("aquarium") ||
    allTypes.has("wildlife_park")
  ) {
    return {
      category: "Zvieratá",
      emoji: "🦁",
    };
  }

  if (
    allTypes.has("amusement_park") ||
    allTypes.has("amusement_center") ||
    allTypes.has("indoor_playground") ||
    allTypes.has("playground") ||
    allTypes.has("miniature_golf_course")
  ) {
    return {
      category: "Zábava",
      emoji: "🎡",
    };
  }

  if (
    allTypes.has("water_park")
  ) {
    return {
      category: "Vodné atrakcie",
      emoji: "🌊",
    };
  }

  if (
    allTypes.has("museum") ||
    allTypes.has("history_museum") ||
    allTypes.has("art_museum") ||
    allTypes.has("art_gallery") ||
    allTypes.has("planetarium")
  ) {
    return {
      category: "Múzeum a poznanie",
      emoji: "🏛️",
    };
  }

  if (
    allTypes.has("castle") ||
    allTypes.has("historical_landmark") ||
    allTypes.has("historical_place") ||
    allTypes.has("cultural_landmark")
  ) {
    return {
      category: "História",
      emoji: "🏰",
    };
  }

  if (
    allTypes.has("national_park") ||
    allTypes.has("city_park") ||
    allTypes.has("park") ||
    allTypes.has("botanical_garden") ||
    allTypes.has("garden") ||
    allTypes.has("hiking_area") ||
    allTypes.has("picnic_ground")
  ) {
    return {
      category: "Príroda",
      emoji: "🌳",
    };
  }

  if (
    allTypes.has("observation_deck")
  ) {
    return {
      category: "Výhľad",
      emoji: "🔭",
    };
  }

  return {
    category: "Rodinný výlet",
    emoji: "🧭",
  };
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
        {
          error: "Povolená je iba POST požiadavka.",
        },
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
        {
          error: "Telo požiadavky nie je platný JSON.",
        },
        400,
      );
    }

    const latitude = Number(body.latitude);
    const longitude = Number(body.longitude);
    const requestedRadiusKm = Number(body.radiusKm ?? 40);

    if (
      !Number.isFinite(latitude) ||
      latitude < -90 ||
      latitude > 90
    ) {
      return jsonResponse(
        {
          error: "Zemepisná šírka nie je správna.",
        },
        400,
      );
    }

    if (
      !Number.isFinite(longitude) ||
      longitude < -180 ||
      longitude > 180
    ) {
      return jsonResponse(
        {
          error: "Zemepisná dĺžka nie je správna.",
        },
        400,
      );
    }

    const radiusKm = Math.min(
      50,
      Math.max(1, requestedRadiusKm),
    );

    const googleResponse = await fetch(
      "https://places.googleapis.com/v1/places:searchNearby",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": googleApiKey,
          "X-Goog-FieldMask": [
            "places.id",
            "places.displayName",
            "places.formattedAddress",
            "places.addressComponents",
            "places.location",
            "places.primaryType",
            "places.types",
            "places.googleMapsUri",
            "places.businessStatus",
          ].join(","),
        },
        body: JSON.stringify({
          includedTypes: familyPlaceTypes,
          maxResultCount: 20,
          rankPreference: "POPULARITY",
          languageCode: "sk",
          locationRestriction: {
            circle: {
              center: {
                latitude,
                longitude,
              },
              radius: radiusKm * 1000,
            },
          },
        }),
      },
    );

    const googleData = await googleResponse.json();

    if (!googleResponse.ok) {
      console.error(
        "Google Nearby Search error:",
        googleData,
      );

      return jsonResponse(
        {
          error:
            googleData?.error?.message ??
            "Google nedokázal nájsť výlety.",
          googleStatus: googleResponse.status,
          googleDetails: googleData?.error?.details ?? null,
        },
        googleResponse.status,
      );
    }

    const places = (
      (googleData.places ?? []) as GooglePlace[]
    )
      .filter((place) => {
        return (
          place.id &&
          place.displayName?.text &&
          Number.isFinite(place.location?.latitude) &&
          Number.isFinite(place.location?.longitude) &&
          place.businessStatus !== "CLOSED_PERMANENTLY"
        );
      })
      .map((place) => {
        const destinationLatitude =
          Number(place.location!.latitude);

        const destinationLongitude =
          Number(place.location!.longitude);

        const categoryInfo = getCategory(
          place.primaryType,
          place.types,
        );

        return {
          placeId: place.id,
          name: place.displayName?.text ?? "Rodinný výlet",
          formattedAddress:
            place.formattedAddress ?? "",
          city:
            getAddressPart(
              place.addressComponents,
              [
                "locality",
                "postal_town",
                "administrative_area_level_3",
              ],
            ) ?? "",
          region:
            getAddressPart(
              place.addressComponents,
              ["administrative_area_level_1"],
            ) ?? "",
          country:
            getAddressPart(
              place.addressComponents,
              ["country"],
            ) ?? "",
          countryCode:
            getAddressPart(
              place.addressComponents,
              ["country"],
              true,
            ) ?? "",
          latitude: destinationLatitude,
          longitude: destinationLongitude,
          primaryType: place.primaryType ?? null,
          types: place.types ?? [],
          category: categoryInfo.category,
          emoji: categoryInfo.emoji,
          distanceKm: calculateDistanceKm(
            latitude,
            longitude,
            destinationLatitude,
            destinationLongitude,
          ),
          googleMapsUrl:
            place.googleMapsUri ?? null,
        };
      })
      .sort((a, b) => a.distanceKm - b.distanceKm);

    return jsonResponse({
      search: {
        latitude,
        longitude,
        requestedRadiusKm,
        usedRadiusKm: radiusKm,
        resultCount: places.length,
      },
      places,
    });
  } catch (error) {
    console.error("discover-places error:", error);

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