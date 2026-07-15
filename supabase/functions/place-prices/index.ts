import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type RequestBody = {
  placeId?: string;
};

type Money = {
  currencyCode?: string;
  units?: string;
  nanos?: number;
};

type PriceRange = {
  startPrice?: Money;
  endPrice?: Money;
};

type GooglePlace = {
  id?: string;
  displayName?: {
    text?: string;
  };
  websiteUri?: string;
  googleMapsUri?: string;
  priceRange?: PriceRange;
  priceLevel?: string;
};

type FetchResult = {
  url: string;
  html: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const PRICE_LINK_KEYWORDS = [
  "cennik",
  "cenník",
  "cenik",
  "ceník",
  "vstupne",
  "vstupné",
  "vstupenky",
  "ticket",
  "tickets",
  "admission",
  "price",
  "pricing",
  "prices",
  "fees",
];

const PRICE_TEXT_KEYWORDS = [
  "dospel",
  "adult",
  "dieťa",
  "dieta",
  "dets",
  "child",
  "rodin",
  "family",
  "senior",
  "študent",
  "student",
  "žiak",
  "ziak",
  "vstup",
  "ticket",
  "osoba",
  "person",
  "skupin",
  "group",
  "zľav",
  "zlav",
  "free",
  "zadarmo",
];

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders,
  });
}

function isPrivateHostname(hostname: string) {
  const host = hostname.toLowerCase();

  if (
    host === "localhost" ||
    host.endsWith(".local") ||
    host === "0.0.0.0" ||
    host === "::1"
  ) {
    return true;
  }

  if (
    host.startsWith("127.") ||
    host.startsWith("10.") ||
    host.startsWith("192.168.")
  ) {
    return true;
  }

  const match172 = host.match(/^172\.(\d{1,3})\./);
  if (match172) {
    const second = Number(match172[1]);
    if (second >= 16 && second <= 31) {
      return true;
    }
  }

  return false;
}

function isSafePublicUrl(value: string | null | undefined) {
  if (!value) {
    return false;
  }

  try {
    const url = new URL(value);

    return (
      (url.protocol === "https:" || url.protocol === "http:") &&
      !isPrivateHostname(url.hostname)
    );
  } catch {
    return false;
  }
}

function normalizeUrl(
  baseUrl: string,
  href: string,
): string | null {
  const cleaned = href.trim();

  if (
    !cleaned ||
    cleaned.startsWith("#") ||
    cleaned.startsWith("mailto:") ||
    cleaned.startsWith("tel:") ||
    cleaned.startsWith("javascript:")
  ) {
    return null;
  }

  try {
    const url = new URL(cleaned, baseUrl);

    if (!isSafePublicUrl(url.toString())) {
      return null;
    }

    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function decodeHtmlEntities(value: string) {
  return value
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&euro;|&#8364;/gi, "€")
    .replace(/&pound;|&#163;/gi, "£")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#(\d+);/g, (_, code) => {
      const number = Number(code);
      return Number.isFinite(number)
        ? String.fromCodePoint(number)
        : "";
    })
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => {
      const number = Number.parseInt(code, 16);
      return Number.isFinite(number)
        ? String.fromCodePoint(number)
        : "";
    });
}

function htmlToLines(html: string) {
  const withoutNoise = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "\n")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "\n")
    .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, "\n")
    .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, "\n")
    .replace(
      /<(br|\/p|\/div|\/li|\/tr|\/td|\/th|\/h[1-6])\b[^>]*>/gi,
      "\n",
    )
    .replace(/<[^>]+>/g, " ");

  return decodeHtmlEntities(withoutNoise)
    .split(/\r?\n/)
    .map((line) =>
      line
        .replace(/\s+/g, " ")
        .replace(/\u00a0/g, " ")
        .trim()
    )
    .filter((line) => line.length >= 3 && line.length <= 280);
}

function extractJsonLdText(html: string) {
  const texts: string[] = [];
  const regex =
    /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;

  let match: RegExpExecArray | null;

  while ((match = regex.exec(html)) !== null) {
    const raw = decodeHtmlEntities(match[1] ?? "").trim();

    if (!raw) {
      continue;
    }

    try {
      const parsed = JSON.parse(raw);
      texts.push(JSON.stringify(parsed));
    } catch {
      texts.push(raw);
    }
  }

  return texts;
}

function containsCurrency(line: string) {
  return /(?:\d[\d\s]*[.,]?\d*)\s*(?:€|EUR|Kč|CZK|eur|czk)\b/i.test(
    line,
  );
}

function containsPriceKeyword(line: string) {
  const normalized = line.toLowerCase();

  return PRICE_TEXT_KEYWORDS.some((keyword) =>
    normalized.includes(keyword)
  );
}

function extractPriceLines(html: string) {
  const visibleLines = htmlToLines(html);
  const jsonLdLines = extractJsonLdText(html)
    .flatMap((text) => text.split(/[{},]/))
    .map((line) => line.replace(/["\\]/g, " ").replace(/\s+/g, " ").trim())
    .filter(Boolean);

  const allLines = [...visibleLines, ...jsonLdLines];
  const selected: string[] = [];

  for (let index = 0; index < allLines.length; index += 1) {
    const line = allLines[index];

    if (!containsCurrency(line)) {
      continue;
    }

    const previous = allLines[index - 1] ?? "";
    const next = allLines[index + 1] ?? "";
    const combined = [previous, line, next]
      .filter(Boolean)
      .join(" • ")
      .replace(/\s+/g, " ")
      .trim();

    if (
      containsPriceKeyword(line) ||
      containsPriceKeyword(previous) ||
      containsPriceKeyword(next)
    ) {
      selected.push(combined);
    } else if (line.length <= 140) {
      selected.push(line);
    }
  }

  const unique: string[] = [];
  const seen = new Set<string>();

  for (const line of selected) {
    const key = line.toLowerCase();

    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    unique.push(line);

    if (unique.length >= 12) {
      break;
    }
  }

  return unique;
}

function findCandidatePriceUrls(
  baseUrl: string,
  html: string,
) {
  const candidates: string[] = [];
  const seen = new Set<string>();

  const linkRegex =
    /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;

  let match: RegExpExecArray | null;

  while ((match = linkRegex.exec(html)) !== null) {
    const href = match[1] ?? "";
    const anchorText = decodeHtmlEntities(
      (match[2] ?? "").replace(/<[^>]+>/g, " "),
    )
      .replace(/\s+/g, " ")
      .trim();

    const haystack = `${href} ${anchorText}`.toLowerCase();

    if (
      !PRICE_LINK_KEYWORDS.some((keyword) =>
        haystack.includes(keyword)
      )
    ) {
      continue;
    }

    const normalized = normalizeUrl(baseUrl, href);

    if (!normalized || seen.has(normalized)) {
      continue;
    }

    seen.add(normalized);
    candidates.push(normalized);

    if (candidates.length >= 4) {
      break;
    }
  }

  return candidates;
}

async function fetchHtml(
  url: string,
  timeoutMs = 9000,
): Promise<FetchResult | null> {
  if (!isSafePublicUrl(url)) {
    return null;
  }

  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    timeoutMs,
  );

  try {
    const response = await fetch(url, {
      method: "GET",
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (compatible; RodinnyRadar/1.0; +https://supabase.com)",
        "Accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.5",
        "Accept-Language": "sk,cs;q=0.9,en;q=0.7",
      },
    });

    const contentType =
      response.headers.get("content-type") ?? "";

    if (
      !response.ok ||
      !contentType.toLowerCase().includes("text/html")
    ) {
      return null;
    }

    const html = await response.text();

    return {
      url: response.url || url,
      html: html.slice(0, 1_500_000),
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function moneyToNumber(
  money: Money | null | undefined,
): number | null {
  if (!money) {
    return null;
  }

  const units = Number(money.units ?? 0);
  const nanos = Number(money.nanos ?? 0);

  if (!Number.isFinite(units) || !Number.isFinite(nanos)) {
    return null;
  }

  return units + nanos / 1_000_000_000;
}

function formatMoney(
  amount: number,
  currencyCode: string,
) {
  try {
    return new Intl.NumberFormat("sk-SK", {
      style: "currency",
      currency: currencyCode,
      maximumFractionDigits: 2,
    }).format(amount);
  } catch {
    return `${amount.toFixed(2)} ${currencyCode}`;
  }
}

function formatGooglePriceRange(
  priceRange: PriceRange | null | undefined,
) {
  if (!priceRange) {
    return null;
  }

  const start = moneyToNumber(priceRange.startPrice);
  const end = moneyToNumber(priceRange.endPrice);
  const currencyCode =
    priceRange.startPrice?.currencyCode ??
    priceRange.endPrice?.currencyCode ??
    "";

  if (!currencyCode || start === null) {
    return null;
  }

  if (end === null) {
    return `Od ${formatMoney(start, currencyCode)}`;
  }

  return `${formatMoney(start, currencyCode)} – ${formatMoney(
    end,
    currencyCode,
  )}`;
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

    let body: RequestBody;

    try {
      body = await req.json();
    } catch {
      return jsonResponse(
        { error: "Telo požiadavky nie je platný JSON." },
        400,
      );
    }

    const placeId = body.placeId?.trim();

    if (!placeId) {
      return jsonResponse(
        { error: "Chýba placeId výletu." },
        400,
      );
    }

    const googleResponse = await fetch(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?languageCode=sk`,
      {
        method: "GET",
        headers: {
          "X-Goog-Api-Key": googleApiKey,
          "X-Goog-FieldMask": [
            "id",
            "displayName",
            "websiteUri",
            "googleMapsUri",
            "priceRange",
            "priceLevel",
          ].join(","),
        },
      },
    );

    const googleText = await googleResponse.text();
    let googleData: GooglePlace = {};

    if (googleText.trim()) {
      try {
        googleData = JSON.parse(googleText) as GooglePlace;
      } catch {
        return jsonResponse(
          {
            error:
              "Google vrátil nečitateľnú odpoveď pri zisťovaní ceny.",
          },
          502,
        );
      }
    }

    if (!googleResponse.ok) {
      return jsonResponse(
        {
          error:
            "Nepodarilo sa načítať zdroj ceny z Google.",
          googleStatus: googleResponse.status,
          googleBody: googleData,
        },
        googleResponse.status,
      );
    }

    const websiteUrl = googleData.websiteUri ?? null;
    const googlePriceRangeLabel =
      formatGooglePriceRange(googleData.priceRange);

    if (!websiteUrl || !isSafePublicUrl(websiteUrl)) {
      return jsonResponse({
        price: {
          placeId,
          placeName:
            googleData.displayName?.text ?? "",
          status: googlePriceRangeLabel
            ? "google_range"
            : "no_official_website",
          priceLines: [],
          googlePriceRangeLabel,
          priceLevel:
            googleData.priceLevel ?? null,
          sourceUrl:
            googleData.googleMapsUri ?? null,
          sourceType: googlePriceRangeLabel
            ? "google"
            : "none",
          checkedAt: new Date().toISOString(),
          note: googlePriceRangeLabel
            ? "Google uvádza cenový rozsah, nie rozdelenie na dospelého, dieťa a rodinu."
            : "Google pre toto miesto neuvádza oficiálny web ani presný cenník.",
        },
      });
    }

    const homepage = await fetchHtml(websiteUrl);

    if (!homepage) {
      return jsonResponse({
        price: {
          placeId,
          placeName:
            googleData.displayName?.text ?? "",
          status: googlePriceRangeLabel
            ? "google_range"
            : "website_unavailable",
          priceLines: [],
          googlePriceRangeLabel,
          priceLevel:
            googleData.priceLevel ?? null,
          sourceUrl: websiteUrl,
          sourceType: googlePriceRangeLabel
            ? "google"
            : "official_website",
          checkedAt: new Date().toISOString(),
          note:
            "Oficiálna stránka sa nedala automaticky prečítať. Cenu overte otvorením zdroja.",
        },
      });
    }

    const candidateUrls = [
      homepage.url,
      ...findCandidatePriceUrls(
        homepage.url,
        homepage.html,
      ),
    ];

    let bestLines = extractPriceLines(homepage.html);
    let bestSourceUrl = homepage.url;

    for (const candidateUrl of candidateUrls.slice(1, 4)) {
      const page = await fetchHtml(candidateUrl);

      if (!page) {
        continue;
      }

      const lines = extractPriceLines(page.html);

      if (lines.length > bestLines.length) {
        bestLines = lines;
        bestSourceUrl = page.url;
      }

      if (bestLines.length >= 6) {
        break;
      }
    }

    return jsonResponse({
      price: {
        placeId,
        placeName:
          googleData.displayName?.text ?? "",
        status:
          bestLines.length > 0
            ? "found_on_official_website"
            : googlePriceRangeLabel
              ? "google_range"
              : "not_found",
        priceLines: bestLines,
        googlePriceRangeLabel,
        priceLevel:
          googleData.priceLevel ?? null,
        sourceUrl: bestSourceUrl,
        sourceType:
          bestLines.length > 0
            ? "official_website"
            : googlePriceRangeLabel
              ? "google"
              : "official_website",
        checkedAt: new Date().toISOString(),
        note:
          bestLines.length > 0
            ? "Ceny boli automaticky nájdené na oficiálnej stránke. Pred návštevou ich ešte skontrolujte v zdroji."
            : "Automatika nenašla čitateľný cenník. Stránka môže používať PDF, JavaScript alebo blokovať automatické čítanie.",
      },
    });
  } catch (error) {
    console.error("place-prices error:", error);

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