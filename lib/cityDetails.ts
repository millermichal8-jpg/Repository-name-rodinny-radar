export type CityDetails = {
  placeId: string;
  name: string;
  formattedAddress: string;
  latitude: number;
  longitude: number;
  countryCode: string | null;
  country: string | null;
  region: string | null;
  googleMapsUrl: string | null;
};

type CityDetailsResponse = {
  city?: CityDetails;
  error?: string;
};

const CITY_DETAILS_URL =
  'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/city-details';

export async function getCityDetails(
  placeId: string,
): Promise<CityDetails> {
  const response = await fetch(CITY_DETAILS_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ placeId }),
  });

  const rawText = await response.text();

  let data: CityDetailsResponse;

  try {
    data = JSON.parse(rawText) as CityDetailsResponse;
  } catch {
    throw new Error('Server vrátil nečitateľnú odpoveď mesta.');
  }

  if (!response.ok || !data.city) {
    throw new Error(
      data.error ?? `Načítanie GPS zlyhalo (${response.status}).`,
    );
  }

  return data.city;
}
