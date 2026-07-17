export type ExperienceFeedEvent = {
  id: string;
  title: string;
  summary: string | null;
  imageUrl: string | null;
  venueName: string | null;
  city: string | null;
  region: string | null;
  countryCode: string | null;
  latitude: number | null;
  longitude: number | null;
  distanceKm: number | null;
  categoryCode: string | null;
  categoryName: string | null;
  emoji: string;
  startsAt: string | null;
  endsAt: string | null;
  allDay: boolean;
  priceMin: number | null;
  priceMax: number | null;
  currency: string;
  offerName: string | null;
  purchaseUrl: string | null;
  freeEntry: boolean;
  familyScore: number;
  qualityScore: number;
};

type ExperienceFeedResponse = {
  search?: {
    latitude: number;
    longitude: number;
    radiusKm: number;
    resultCount: number;
    from: string;
    to: string;
  };
  events?: ExperienceFeedEvent[];
  error?: string;
};

const EXPERIENCE_FEED_URL =
  'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/experience-feed';

export async function getExperienceFeed(input: {
  latitude: number;
  longitude: number;
  radiusKm: number;
  childrenAges: number[];
  freeOnly?: boolean;
  limit?: number;
}) {
  const minChildAge = input.childrenAges.length > 0
    ? Math.min(...input.childrenAges)
    : undefined;
  const maxChildAge = input.childrenAges.length > 0
    ? Math.max(...input.childrenAges)
    : undefined;

  const response = await fetch(EXPERIENCE_FEED_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      latitude: input.latitude,
      longitude: input.longitude,
      radiusKm: input.radiusKm,
      minChildAge,
      maxChildAge,
      freeOnly: Boolean(input.freeOnly),
      limit: input.limit ?? 30,
    }),
  });

  const rawText = await response.text();
  let data: ExperienceFeedResponse;

  try {
    data = JSON.parse(rawText) as ExperienceFeedResponse;
  } catch {
    throw new Error('Server vrátil nečitateľný zoznam podujatí.');
  }

  if (!response.ok || !Array.isArray(data.events)) {
    throw new Error(
      data.error ?? `Načítanie podujatí zlyhalo (${response.status}).`,
    );
  }

  return {
    search: data.search,
    events: data.events,
  };
}
