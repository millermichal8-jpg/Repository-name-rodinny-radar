export type PlaceDetails = {
  placeId: string;
  name: string;
  formattedAddress: string;
  googleMapsUrl: string | null;
  websiteUrl: string | null;
  phone: string | null;
  rating: number | null;
  userRatingCount: number;
  priceLevel: string | null;
  priceLabel: string | null;
  businessStatus: string | null;
  businessStatusLabel: string | null;
  openNow: boolean | null;
  nextOpenTime: string | null;
  nextCloseTime: string | null;
  openingHours: string[];
};

type PlaceDetailsResponse = {
  place?: PlaceDetails;
  error?: string;
};

const PLACE_DETAILS_URL =
  'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/place-details-v2';

export async function getPlaceDetails(
  placeId: string,
): Promise<PlaceDetails> {
  const response = await fetch(PLACE_DETAILS_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ placeId }),
  });

  const rawText = await response.text();

  let data: PlaceDetailsResponse;

  try {
    data = JSON.parse(rawText) as PlaceDetailsResponse;
  } catch {
    throw new Error(
      'Server vrátil nečitateľný detail výletu.',
    );
  }

  if (!response.ok || !data.place) {
    throw new Error(
      data.error ??
        `Načítanie detailu zlyhalo (${response.status}).`,
    );
  }

  return data.place;
}
