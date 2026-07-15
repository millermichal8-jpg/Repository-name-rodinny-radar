export type DiscoveredPlace = {
  placeId: string;
  name: string;
  formattedAddress: string;
  city: string;
  region: string;
  country: string;
  countryCode: string;
  latitude: number;
  longitude: number;
  primaryType: string | null;
  types: string[];
  category: string;
  emoji: string;
  distanceKm: number;
  googleMapsUrl: string | null;
};

type DiscoverPlacesResponse = {
  search?: {
    latitude: number;
    longitude: number;
    requestedRadiusKm: number;
    usedRadiusKm: number;
    resultCount: number;
  };
  places?: DiscoveredPlace[];
  error?: string;
};

const DISCOVER_PLACES_URL =
  'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/discover-places';

export async function discoverPlaces(input: {
  latitude: number;
  longitude: number;
  radiusKm: number;
}) {
  const response = await fetch(DISCOVER_PLACES_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(input),
  });

  const rawText = await response.text();

  let data: DiscoverPlacesResponse;

  try {
    data = JSON.parse(rawText) as DiscoverPlacesResponse;
  } catch {
    throw new Error('Server vrátil nečitateľný zoznam výletov.');
  }

  if (!response.ok || !data.search || !Array.isArray(data.places)) {
    throw new Error(
      data.error ?? `Vyhľadanie výletov zlyhalo (${response.status}).`,
    );
  }

  return {
    search: data.search,
    places: data.places,
  };
}
