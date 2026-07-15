export type CitySuggestion = {
  placeId: string;
  name: string;
  area: string;
  fullText: string;
  types: string[];
};

type CitySearchResponse = {
  suggestions?: CitySuggestion[];
  error?: string;
};

const CITY_SEARCH_URL =
  'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/city-search';

export async function searchCities(
  input: string,
): Promise<CitySuggestion[]> {
  const query = input.trim();

  if (query.length < 2) {
    return [];
  }

  const response = await fetch(CITY_SEARCH_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ input: query }),
  });

  const rawText = await response.text();

  let data: CitySearchResponse;

  try {
    data = JSON.parse(rawText) as CitySearchResponse;
  } catch {
    throw new Error('Server vrátil nečitateľnú odpoveď.');
  }

  if (!response.ok) {
    throw new Error(
      data.error ?? `Vyhľadávanie miest zlyhalo (${response.status}).`,
    );
  }

  return Array.isArray(data.suggestions)
    ? data.suggestions
    : [];
}
