export type PlacePriceInfo = {
  placeId: string;
  placeName: string;
  status:
    | 'found_on_official_website'
    | 'google_range'
    | 'no_official_website'
    | 'website_unavailable'
    | 'not_found';
  priceLines: string[];
  googlePriceRangeLabel: string | null;
  priceLevel: string | null;
  sourceUrl: string | null;
  sourceType: 'official_website' | 'google' | 'none';
  checkedAt: string;
  note: string;
};

type PlacePriceResponse = {
  price?: PlacePriceInfo;
  error?: string;
};

const PLACE_PRICES_URL =
  'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/place-prices';

export async function getPlacePrices(
  placeId: string,
): Promise<PlacePriceInfo> {
  const response = await fetch(PLACE_PRICES_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ placeId }),
  });

  const rawText = await response.text();

  let data: PlacePriceResponse;

  try {
    data = JSON.parse(rawText) as PlacePriceResponse;
  } catch {
    throw new Error(
      'Server vrátil nečitateľnú odpoveď o cenách.',
    );
  }

  if (!response.ok || !data.price) {
    throw new Error(
      data.error ??
        `Načítanie cien zlyhalo (${response.status}).`,
    );
  }

  return data.price;
}
