import { createClient } from "npm:@supabase/supabase-js@2.57.0";
import * as cheerio from "npm:cheerio@1.0.0";

type JsonObject = Record<string, unknown>;

type SourceConfig = {
  allowedPathRegex?: string;
  allowedUrlRegex?: string;
  excludeUrlRegex?: string;
  minimumQuality?: number;
  maximumFutureDays?: number;
  cardSelector?: string;
  linkSelector?: string;
  titleSelector?: string;
  dateSelector?: string;
  venueSelector?: string;
  descriptionSelector?: string;
  imageSelector?: string;
  allowExternalHost?: boolean;
  defaultCurrency?: "EUR" | "CZK";
};

type SourcePage = {
  code: string;
  display_name: string;
  source_code: string;
  list_url: string;
  adapter: string;
  country_code: string;
  default_city: string | null;
  default_region: string | null;
  max_event_links: number;
  config: SourceConfig;
  group_code?: string | null;
  priority?: number | null;
  cron_enabled?: boolean | null;
};

type EventCandidate = {
  sourceCode: string;
  sourcePageCode: string;
  sourceUrl: string;
  externalId: string;
  title: string;
  summary: string | null;
  description: string | null;
  startDate: string | null;
  endDate: string | null;
  allDay: boolean;
  city: string | null;
  region: string | null;
  countryCode: string;
  venueName: string | null;
  address: string | null;
  imageUrl: string | null;
  freeEntry: boolean;
  priceMin: number | null;
  priceMax: number | null;
  currency: string;
  purchaseUrl: string | null;
  qualityScore: number;
  warnings: string[];
  canceled: boolean;
  parser: "jsonld" | "citio-detail" | "webygroup-detail" | "ticketware-card" | "generic-detail" | "generic-card";
  raw: JsonObject;
};

type ParsedDateRange = {
  startDate: string | null;
  endDate: string | null;
  allDay: boolean;
};

type ValidationResult = {
  accepted: boolean;
  reason: string | null;
};

const DAY_MS = 86_400_000;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sync-token",
};
const USER_AGENT =
  "RodinnyRadarBot/4.0 (+official municipal event indexing; contact: project owner)";

const BLOCKED_TITLES = new Set([
  "podujatia",
  "aktualne podujatia",
  "kulturne a sportove akcie",
  "program",
  "uvod",
  "o nas",
  "organizacne zaradenie",
  "referencie",
  "pre umelcov",
  "kontakty",
  "kontakt",
  "mapa stranok",
  "vseobecne obchodne podmienky",
  "zostan informovany o nasich novinkach",
  "pomocnik",
  "online predaj vstupeniek",
  "dorucenie vstupeniek",
  "aplikacia budicheck",
  "darujte svojim blizkym zazitok",
  "kde nas najdete",
  "informacie",
  "fotogaleria",
  "galeria",
  "dolezite odkazy",
  "napiste nam",
  "prihlasovanie na univerzitu tretieho veku je spustene",
  "vsetky akcie",
  "vsetky podujatia",
  "dalsie akcie",
  "dalsie podujatia",
  "zobrazit detail",
  "viac info",
  "detail akce",
  "kalendar akci",
  "kalendar podujati",
]);

const MONTHS: Record<string, number> = {
  januar: 1,
  january: 1,
  leden: 1,
  februar: 2,
  february: 2,
  unor: 2,
  marec: 3,
  march: 3,
  brezen: 3,
  april: 4,
  duben: 4,
  maj: 5,
  may: 5,
  kveten: 5,
  jun: 6,
  june: 6,
  cerven: 6,
  jul: 7,
  july: 7,
  cervenec: 7,
  august: 8,
  srpen: 8,
  september: 9,
  zari: 9,
  oktober: 10,
  october: 10,
  rijen: 10,
  november: 11,
  listopad: 11,
  december: 12,
  prosinec: 12,
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function collapseWhitespace(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function truncate(value: string | null, max: number) {
  if (!value) return null;
  return value.length <= max ? value : `${value.slice(0, max - 1)}…`;
}

function normalizeText(value: string) {
  return collapseWhitespace(value)
    .toLocaleLowerCase("sk")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[–—−]/g, "-")
    .replace(/[^\p{L}\p{N}\s-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeMonth(value: string) {
  return value
    .toLocaleLowerCase("sk")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}

function isBlockedTitle(title: string) {
  const normalized = normalizeText(title);
  if (normalized.length < 4 || normalized.length > 180) return true;
  if (BLOCKED_TITLES.has(normalized)) return true;
  return /^(strana\s+\d+|cookies?|nastavenia cookies|za obsah zodpoveda|technicky prevadzkovatel|zobrazit vsetky podujatia)$/i
    .test(normalized);
}

function cleanAnchorTitle(value: string) {
  let title = collapseWhitespace(value);
  title = title.replace(
    /\s+\d{1,2}\.\s*(?:januar|januára|februar|februára|marec|marca|april|apríla|maj|mája|jun|júna|jul|júla|august|augusta|september|septembra|oktober|októbra|november|novembra|december|decembra)(?:\s*[—–-]\s*\d{1,2}\.\s*(?:[A-Za-zÁ-ž]+))?(?:\s+20\d{2})?.*$/iu,
    "",
  );
  title = title.replace(/\s+\d{1,2}\.\s*[-–—]\s*\d{1,2}\.\d{1,2}\.20\d{2}.*$/u, "");
  title = title.replace(/\s+\d{1,2}\.\d{1,2}\.20\d{2}.*$/u, "");
  return collapseWhitespace(title);
}

function absoluteUrl(href: string, baseUrl: string) {
  try {
    const url = new URL(href, baseUrl);
    if (!['http:', 'https:'].includes(url.protocol)) return null;
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function sameHost(url: string, baseUrl: string) {
  try {
    return new URL(url).hostname === new URL(baseUrl).hostname;
  } catch {
    return false;
  }
}

function safeRegex(pattern: string | undefined) {
  if (!pattern) return null;
  try {
    return new RegExp(pattern, "i");
  } catch {
    return null;
  }
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function fetchHtml(url: string) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const response = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "User-Agent": USER_AGENT,
        Accept: "text/html,application/xhtml+xml",
        "Accept-Language": "sk,cs;q=0.9,en;q=0.4",
        "Cache-Control": "no-cache",
      },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status} pre ${url}`);
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("text/html")) {
      throw new Error(`Nepodporovaný obsah ${contentType} pre ${url}`);
    }
    const html = await response.text();
    if (html.length > 5_000_000) throw new Error(`HTML je príliš veľké pre ${url}`);
    return { html, finalUrl: response.url || url };
  } finally {
    clearTimeout(timeout);
  }
}

function mainScope($: cheerio.CheerioAPI) {
  const selectors = ["main", '[role="main"]', "#content", ".content", ".main-content", "article"];
  for (const selector of selectors) {
    const node = $(selector).first();
    if (node.length && collapseWhitespace(node.text()).length > 100) return node;
  }
  return $("body");
}

function cleanedText($: cheerio.CheerioAPI) {
  const scope = mainScope($).clone();
  scope.find("script,style,noscript,nav,header,footer,form,iframe").remove();
  return collapseWhitespace(scope.text());
}

function lastSundayUtc(year: number, monthIndex: number) {
  const date = new Date(Date.UTC(year, monthIndex + 1, 0));
  return date.getUTCDate() - date.getUTCDay();
}

function bratislavaOffset(year: number, month: number, day: number) {
  const marchLastSunday = lastSundayUtc(year, 2);
  const octoberLastSunday = lastSundayUtc(year, 9);
  const inSummer =
    (month > 3 || (month === 3 && day >= marchLastSunday)) &&
    (month < 10 || (month === 10 && day < octoberLastSunday));
  return inSummer ? "+02:00" : "+01:00";
}

function isValidDateParts(year: number, month: number, day: number) {
  if (year < 2020 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

function isoFromParts(
  year: number,
  month: number,
  day: number,
  hour: number | null,
  minute: number | null,
) {
  if (!isValidDateParts(year, month, day)) return null;
  const pad = (value: number) => String(value).padStart(2, "0");
  const safeHour = hour ?? 12;
  const safeMinute = minute ?? 0;
  return `${year}-${pad(month)}-${pad(day)}T${pad(safeHour)}:${pad(safeMinute)}:00${bratislavaOffset(year, month, day)}`;
}

function parseTime(text: string) {
  const match = text.match(/\b(?:o\s+|od\s+)?([01]?\d|2[0-3])[:.](\d{2})\b/i);
  return match ? { hour: Number(match[1]), minute: Number(match[2]) } : null;
}

function parseSecondTime(text: string) {
  const matches = [...text.matchAll(/\b([01]?\d|2[0-3])[:.](\d{2})\b/g)];
  if (matches.length < 2) return null;
  return { hour: Number(matches[1][1]), minute: Number(matches[1][2]) };
}

function parseHumanDateRange(text: string, yearIfMissing = new Date().getFullYear()): ParsedDateRange {
  const clean = collapseWhitespace(text);
  const firstTime = parseTime(clean);
  const secondTime = parseSecondTime(clean);
  const hour = firstTime?.hour ?? null;
  const minute = firstTime?.minute ?? null;

  let match = clean.match(/\b(\d{1,2})\.(\d{1,2})\.\s*[-–—]\s*(\d{1,2})\.(\d{1,2})\.(20\d{2})\b/);
  if (match) {
    const year = Number(match[5]);
    return {
      startDate: isoFromParts(year, Number(match[2]), Number(match[1]), hour, minute),
      endDate: isoFromParts(year, Number(match[4]), Number(match[3]), 23, 59),
      allDay: !firstTime,
    };
  }

  match = clean.match(/\b(\d{1,2})\.\s*[-–—]\s*(\d{1,2})\.(\d{1,2})\.(20\d{2})\b/);
  if (match) {
    const year = Number(match[4]);
    const month = Number(match[3]);
    return {
      startDate: isoFromParts(year, month, Number(match[1]), hour, minute),
      endDate: isoFromParts(year, month, Number(match[2]), 23, 59),
      allDay: !firstTime,
    };
  }

  match = clean.match(/\bod\s+(\d{1,2})\.\s*([A-Za-zÁ-ž]+)\s+do\s+(\d{1,2})\.\s*([A-Za-zÁ-ž]+)\s+(20\d{2})\b/iu);
  if (match) {
    const startMonth = MONTHS[normalizeMonth(match[2])];
    const endMonth = MONTHS[normalizeMonth(match[4])];
    const year = Number(match[5]);
    if (startMonth && endMonth) {
      return {
        startDate: isoFromParts(year, startMonth, Number(match[1]), hour, minute),
        endDate: isoFromParts(year, endMonth, Number(match[3]), 23, 59),
        allDay: !firstTime,
      };
    }
  }

  match = clean.match(/\b(\d{1,2})\.\s*([A-Za-zÁ-ž]+)\s*[-–—]\s*(\d{1,2})\.\s*([A-Za-zÁ-ž]+)\s+(20\d{2})\b/iu);
  if (match) {
    const startMonth = MONTHS[normalizeMonth(match[2])];
    const endMonth = MONTHS[normalizeMonth(match[4])];
    const year = Number(match[5]);
    if (startMonth && endMonth) {
      return {
        startDate: isoFromParts(year, startMonth, Number(match[1]), hour, minute),
        endDate: isoFromParts(year, endMonth, Number(match[3]), 23, 59),
        allDay: !firstTime,
      };
    }
  }

  match = clean.match(/\b(\d{1,2})\.(\d{1,2})\.(20\d{2})\b/);
  if (match) {
    const year = Number(match[3]);
    const month = Number(match[2]);
    const day = Number(match[1]);
    return {
      startDate: isoFromParts(year, month, day, hour, minute),
      endDate: secondTime
        ? isoFromParts(year, month, day, secondTime.hour, secondTime.minute)
        : null,
      allDay: !firstTime,
    };
  }

  match = clean.match(/\b(\d{1,2})\.\s*([A-Za-zÁ-ž]+)(?:\s+(20\d{2}))?\b/u);
  if (match) {
    const month = MONTHS[normalizeMonth(match[2])];
    const year = match[3] ? Number(match[3]) : yearIfMissing;
    if (month) {
      const day = Number(match[1]);
      return {
        startDate: isoFromParts(year, month, day, hour, minute),
        endDate: secondTime
          ? isoFromParts(year, month, day, secondTime.hour, secondTime.minute)
          : null,
        allDay: !firstTime,
      };
    }
  }

  match = clean.match(/\b(\d{1,2})\.(\d{1,2})\.(?!\d)/);
  if (match) {
    const month = Number(match[2]);
    const day = Number(match[1]);
    return {
      startDate: isoFromParts(yearIfMissing, month, day, hour, minute),
      endDate: secondTime
        ? isoFromParts(yearIfMissing, month, day, secondTime.hour, secondTime.minute)
        : null,
      allDay: !firstTime,
    };
  }

  return { startDate: null, endDate: null, allDay: false };
}

function parseWebygroupDateFields(dateText: string, endText: string | null, timeText: string | null) {
  const startParts = parseHumanDateRange(dateText);
  if (!startParts.startDate) return startParts;

  let startDate = startParts.startDate;
  const time = timeText ? parseTime(timeText) : null;
  if (time) {
    const start = new Date(startDate);
    const year = start.getUTCFullYear();
    const month = start.getUTCMonth() + 1;
    const day = start.getUTCDate();
    startDate = isoFromParts(year, month, day, time.hour, time.minute) ?? startDate;
  }

  let endDate = startParts.endDate;
  if (endText) {
    const endParts = parseHumanDateRange(endText);
    if (endParts.startDate) {
      const end = new Date(endParts.startDate);
      endDate = isoFromParts(
        end.getUTCFullYear(),
        end.getUTCMonth() + 1,
        end.getUTCDate(),
        23,
        59,
      );
    }
  }

  return { startDate, endDate, allDay: !time };
}

function parsePrice(text: string, defaultCurrency: "EUR" | "CZK" = "EUR") {
  const normalized = normalizeText(text);
  const eurValues = [...text.matchAll(/(\d{1,5}(?:[,.]\d{1,2})?)\s*(?:€|EUR)\b/gi)]
    .map((match) => Number(match[1].replace(",", ".")))
    .filter((value) => Number.isFinite(value) && value >= 0 && value < 100_000);
  const czkValues = [...text.matchAll(/(\d{1,6}(?:[,.]\d{1,2})?)\s*(?:Kč|CZK)\b/gi)]
    .map((match) => Number(match[1].replace(",", ".")))
    .filter((value) => Number.isFinite(value) && value >= 0 && value < 1_000_000);
  const currency = czkValues.length > eurValues.length ? "CZK" : eurValues.length ? "EUR" : defaultCurrency;
  const values = currency === "CZK" ? czkValues : eurValues;
  const freeEntry = /\b(vstup volny|vstup zdarma|zadarmo|bezplatne|bezplatny|vstup zdarma|zdarma|vstup volny|bezplatne)\b/i.test(normalized) ||
    (values.length > 0 && values.every((value) => value === 0));
  if (freeEntry) {
    return { freeEntry: true, priceMin: 0, priceMax: 0, currency };
  }
  return {
    freeEntry: false,
    priceMin: values.length ? Math.min(...values) : null,
    priceMax: values.length ? Math.max(...values) : null,
    currency,
  };
}

function isCanceledText(text: string) {
  return /\b(zrusene|zrušené|zruseny|zrušený|cancelled|canceled|odvolane|odvolané)\b/i
    .test(normalizeText(text));
}

function extractJsonLd($: cheerio.CheerioAPI) {
  const nodes: unknown[] = [];
  $('script[type="application/ld+json"]').each((_index: number, element: any) => {
    const raw = $(element).text().trim();
    if (!raw) return;
    try {
      nodes.push(JSON.parse(raw));
    } catch {
      // Broken JSON-LD is ignored. A source-specific parser remains available.
    }
  });
  return nodes;
}

function walkJson(value: unknown, output: JsonObject[]) {
  if (Array.isArray(value)) {
    for (const item of value) walkJson(item, output);
    return;
  }
  if (!isObject(value)) return;
  if (value["@graph"]) walkJson(value["@graph"], output);
  const rawType = value["@type"];
  const types = Array.isArray(rawType) ? rawType : [rawType];
  if (types.some((type) => typeof type === "string" && (type === "Event" || type.endsWith("Event")))) {
    output.push(value);
  }
}

function objectValue(value: unknown): JsonObject | null {
  if (isObject(value)) return value;
  if (Array.isArray(value)) return value.find(isObject) ?? null;
  return null;
}

function textValue(value: unknown): string | null {
  if (typeof value === "string") return collapseWhitespace(value);
  if (Array.isArray(value)) return value.map(textValue).filter(Boolean).join(", ") || null;
  if (isObject(value)) {
    return getString(value.name) ?? getString(value.streetAddress) ?? getString(value.url) ?? null;
  }
  return null;
}

function firstUrl(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    for (const item of value) {
      const result = firstUrl(item);
      if (result) return result;
    }
  }
  if (isObject(value)) {
    return getString(value.url) ?? getString(value.contentUrl) ?? getString(value["@id"]);
  }
  return null;
}

async function candidateFromJsonLd(
  event: JsonObject,
  source: SourcePage,
  sourceUrl: string,
): Promise<EventCandidate | null> {
  const title = textValue(event.name);
  if (!title || isBlockedTitle(title)) return null;

  const startDateText = textValue(event.startDate);
  const endDateText = textValue(event.endDate);
  const startDate = startDateText ? new Date(startDateText) : null;
  const endDate = endDateText ? new Date(endDateText) : null;
  const startIso = startDate && !Number.isNaN(startDate.getTime()) ? startDate.toISOString() : null;
  const endIso = endDate && !Number.isNaN(endDate.getTime()) ? endDate.toISOString() : null;
  if (!startIso) return null;

  const location = objectValue(event.location);
  const addressObject = location ? objectValue(location.address) : null;
  const address = addressObject
    ? [
      getString(addressObject.streetAddress),
      getString(addressObject.postalCode),
      getString(addressObject.addressLocality),
    ].filter(Boolean).join(", ") || null
    : textValue(location?.address);

  const offers = Array.isArray(event.offers)
    ? event.offers.filter(isObject)
    : objectValue(event.offers)
    ? [objectValue(event.offers)!]
    : [];
  const offerText = offers.map((offer) => `${offer.price ?? ""} ${offer.priceCurrency ?? ""}`).join(" ");
  const defaultCurrency = source.config?.defaultCurrency ?? (source.country_code === "CZ" ? "CZK" : "EUR");
  const price = parsePrice(offerText, defaultCurrency);
  const numericPrices = offers
    .map((offer) => Number(offer.price))
    .filter((value) => Number.isFinite(value) && value >= 0);
  if (numericPrices.length) {
    price.priceMin = Math.min(...numericPrices);
    price.priceMax = Math.max(...numericPrices);
    price.freeEntry = numericPrices.every((value) => value === 0);
  }

  const canceled = isCanceledText(`${textValue(event.eventStatus) ?? ""} ${title}`);
  const externalId = await sha256(
    `${source.source_code}|${textValue(event["@id"]) ?? sourceUrl}|${title}|${startIso}`,
  );
  let qualityScore = 75;
  if (location || source.default_city) qualityScore += 8;
  if (event.description) qualityScore += 6;
  if (event.image) qualityScore += 6;
  if (price.freeEntry || price.priceMin !== null) qualityScore += 5;

  return {
    sourceCode: source.source_code,
    sourcePageCode: source.code,
    sourceUrl,
    externalId,
    title,
    summary: truncate(textValue(event.description), 500),
    description: truncate(textValue(event.description), 4000),
    startDate: startIso,
    endDate: endIso,
    allDay: !startDateText?.includes("T"),
    city: getString(addressObject?.addressLocality) ?? source.default_city,
    region: getString(addressObject?.addressRegion) ?? source.default_region,
    countryCode: source.country_code,
    venueName: textValue(location?.name),
    address,
    imageUrl: firstUrl(event.image),
    freeEntry: price.freeEntry,
    priceMin: price.priceMin,
    priceMax: price.priceMax,
    currency: offers.map((offer) => getString(offer.priceCurrency)).find(Boolean) ?? defaultCurrency,
    purchaseUrl: offers.map((offer) => firstUrl(offer.url)).find(Boolean) ?? firstUrl(event.url),
    qualityScore: Math.min(100, qualityScore),
    warnings: canceled ? ["Podujatie je zrušené"] : [],
    canceled,
    parser: "jsonld",
    raw: event,
  };
}

function discoverExactLinks(
  html: string,
  finalUrl: string,
  pattern: RegExp,
  limit: number,
) {
  const $ = cheerio.load(html);
  const links = new Map<string, string>();
  mainScope($).find("a[href]").each((_index: number, element: any) => {
    const href = $(element).attr("href");
    if (!href) return;
    const url = absoluteUrl(href, finalUrl);
    if (!url || !sameHost(url, finalUrl)) return;
    if (!pattern.test(new URL(url).pathname)) return;
    const title = cleanAnchorTitle($(element).text());
    if (!title || isBlockedTitle(title)) return;
    const previous = links.get(url);
    if (!previous || title.length > previous.length) links.set(url, title);
  });
  return [...links.entries()].slice(0, limit).map(([url, title]) => ({ url, title }));
}

function extractSectionWindow(text: string, startTitle: string, stopWords: string[]) {
  const startIndex = normalizeText(text).indexOf(normalizeText(startTitle));
  let result = startIndex >= 0 ? text.slice(startIndex + startTitle.length) : text;
  let stopIndex = result.length;
  for (const word of stopWords) {
    const index = normalizeText(result).indexOf(normalizeText(word));
    if (index >= 0) stopIndex = Math.min(stopIndex, index);
  }
  return collapseWhitespace(result.slice(0, stopIndex));
}

function findImage($: cheerio.CheerioAPI, sourceUrl: string) {
  const raw = getString($('meta[property="og:image"]').attr("content")) ??
    getString(mainScope($).find("img[src]").toArray()
      .map((element: any) => $(element).attr("src"))
      .find((src: string | undefined) => src && !/logo|icon|avatar|banner/i.test(src)));
  return raw ? absoluteUrl(raw, sourceUrl) : null;
}


type GenericCardSeed = {
  sourceUrl: string;
  title: string;
  text: string;
  date: ParsedDateRange;
  venueName: string | null;
  imageUrl: string | null;
};

function regexMatches(value: string, pattern: string | undefined) {
  if (!pattern) return true;
  const regex = safeRegex(pattern);
  return regex ? regex.test(value) : false;
}

function allowedGenericUrl(source: SourcePage, url: string, baseUrl: string) {
  if (!source.config?.allowExternalHost && !sameHost(url, baseUrl)) return false;
  const target = `${new URL(url).pathname}${new URL(url).search}`;
  if (source.config?.allowedUrlRegex && !regexMatches(url, source.config.allowedUrlRegex)) return false;
  if (source.config?.allowedPathRegex && !regexMatches(target, source.config.allowedPathRegex)) return false;
  if (source.config?.excludeUrlRegex && regexMatches(url, source.config.excludeUrlRegex)) return false;
  return true;
}

function parseDateTimeAttribute(value: string | undefined | null): ParsedDateRange | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return {
    startDate: date.toISOString(),
    endDate: null,
    allDay: !value.includes("T") && !value.includes(":"),
  };
}

function extractVenueFromText(text: string) {
  const match = text.match(/(?:Miesto|Místo|Kde|Venue)\s*:?\s*([^|•\n]{2,140})/iu);
  return match ? collapseWhitespace(match[1]) : null;
}

function selectorText(
  $: cheerio.CheerioAPI,
  scope: cheerio.Cheerio<cheerio.AnyNode>,
  selector: string | undefined,
) {
  if (!selector) return null;
  try {
    return getString(collapseWhitespace(scope.find(selector).first().text()));
  } catch {
    return null;
  }
}

function selectorImage(
  $: cheerio.CheerioAPI,
  scope: cheerio.Cheerio<cheerio.AnyNode>,
  selector: string | undefined,
  baseUrl: string,
) {
  if (!selector) return null;
  try {
    const raw = scope.find(selector).first().attr("src") ?? scope.find(selector).first().attr("data-src");
    return raw ? absoluteUrl(raw, baseUrl) : null;
  } catch {
    return null;
  }
}

function bestGenericTitle(
  $: cheerio.CheerioAPI,
  source: SourcePage,
  fallbackTitle: string,
) {
  const configured = source.config?.titleSelector
    ? getString($(source.config.titleSelector).first().text())
    : null;
  const title = cleanAnchorTitle(
    configured ??
      getString($("main h1, article h1, h1").first().text()) ??
      getString($('meta[property="og:title"]').attr("content")) ??
      fallbackTitle,
  );
  return title && !isBlockedTitle(title) ? title : null;
}

async function parseGenericDetail(
  source: SourcePage,
  sourceUrl: string,
  fallbackTitle: string,
  seed?: GenericCardSeed,
): Promise<EventCandidate | null> {
  const { html, finalUrl } = await fetchHtml(sourceUrl);
  const $ = cheerio.load(html);
  const jsonEvents: JsonObject[] = [];
  for (const root of extractJsonLd($)) walkJson(root, jsonEvents);
  for (const event of jsonEvents) {
    const candidate = await candidateFromJsonLd(event, source, finalUrl);
    if (candidate) return { ...candidate, parser: "jsonld" };
  }

  const title = bestGenericTitle($, source, fallbackTitle);
  if (!title) return null;
  const scope = mainScope($);
  const fullText = cleanedText($);
  const configuredDescription = selectorText($, scope, source.config?.descriptionSelector);
  const metaDescription = getString($('meta[name="description"]').attr("content")) ??
    getString($('meta[property="og:description"]').attr("content"));
  const description = collapseWhitespace(
    configuredDescription ?? metaDescription ?? extractSectionWindow(fullText, title, [
      "Podobné",
      "Súvisiace",
      "Další akce",
      "Ďalšie podujatia",
      "Kontakt",
      "Technický prevádzkovateľ",
    ]),
  );

  const configuredDateText = selectorText($, scope, source.config?.dateSelector);
  const dateTimeAttr = scope.find("time[datetime]").first().attr("datetime");
  const parsedAttr = parseDateTimeAttribute(dateTimeAttr);
  const date = parsedAttr?.startDate
    ? parsedAttr
    : parseHumanDateRange(configuredDateText ?? `${seed?.text ?? ""} ${fullText.slice(0, 1800)}`);
  if (!date.startDate && seed?.date.startDate) {
    date.startDate = seed.date.startDate;
    date.endDate = seed.date.endDate;
    date.allDay = seed.date.allDay;
  }
  if (!date.startDate) return null;

  const venueName = selectorText($, scope, source.config?.venueSelector) ??
    extractVenueFromText(`${seed?.text ?? ""} ${fullText.slice(0, 2200)}`) ??
    seed?.venueName ??
    source.default_city;
  const imageUrl = selectorImage($, scope, source.config?.imageSelector, finalUrl) ??
    findImage($, finalUrl) ?? seed?.imageUrl ?? null;
  const defaultCurrency = source.config?.defaultCurrency ?? (source.country_code === "CZ" ? "CZK" : "EUR");
  const price = parsePrice(`${seed?.text ?? ""} ${description}`, defaultCurrency);
  const canceled = isCanceledText(`${title} ${description}`);
  const externalId = await sha256(`${source.source_code}|${finalUrl}|${title}|${date.startDate}`);
  let qualityScore = 72;
  if (source.default_city || venueName) qualityScore += 8;
  if (imageUrl) qualityScore += 5;
  if (description.length > 100) qualityScore += 6;
  if (price.freeEntry || price.priceMin !== null) qualityScore += 5;
  if (date.endDate) qualityScore += 2;

  return {
    sourceCode: source.source_code,
    sourcePageCode: source.code,
    sourceUrl: finalUrl,
    externalId,
    title,
    summary: truncate(description, 500),
    description: truncate(description, 4000),
    startDate: date.startDate,
    endDate: date.endDate,
    allDay: date.allDay,
    city: source.default_city,
    region: source.default_region,
    countryCode: source.country_code,
    venueName,
    address: venueName,
    imageUrl,
    freeEntry: price.freeEntry,
    priceMin: price.priceMin,
    priceMax: price.priceMax,
    currency: price.currency,
    purchaseUrl: finalUrl,
    qualityScore: Math.min(100, qualityScore),
    warnings: canceled ? ["Podujatie je zrušené"] : [],
    canceled,
    parser: "generic-detail",
    raw: {
      parser: "generic-detail-v4",
      seedText: truncate(seed?.text ?? null, 1200),
      configuredDateText,
      dateTimeAttr,
    },
  };
}

function findGenericCard(
  $: cheerio.CheerioAPI,
  anchor: cheerio.Cheerio<cheerio.AnyNode>,
  source: SourcePage,
  finalUrl: string,
): GenericCardSeed | null {
  const href = anchor.attr("href");
  if (!href) return null;
  const sourceUrl = absoluteUrl(href, finalUrl);
  if (!sourceUrl || !allowedGenericUrl(source, sourceUrl, finalUrl)) return null;

  let node = source.config?.cardSelector ? anchor.closest(source.config.cardSelector) : anchor.parent();
  for (let depth = 0; depth < 7 && node.length; depth += 1) {
    const text = collapseWhitespace(node.text());
    if (text.length >= 12 && text.length <= 2600) {
      const configuredTitle = selectorText($, node, source.config?.titleSelector);
      const headingTitle = getString(node.find("h1,h2,h3,h4").first().text());
      const title = cleanAnchorTitle(configuredTitle ?? headingTitle ?? anchor.text());
      const configuredDate = selectorText($, node, source.config?.dateSelector);
      const timeDate = parseDateTimeAttribute(node.find("time[datetime]").first().attr("datetime"));
      const date = timeDate?.startDate ? timeDate : parseHumanDateRange(configuredDate ?? text);
      if (title && !isBlockedTitle(title) && date.startDate) {
        const venueName = selectorText($, node, source.config?.venueSelector) ?? extractVenueFromText(text);
        const imageUrl = selectorImage($, node, source.config?.imageSelector ?? "img", finalUrl);
        return { sourceUrl, title, text, date, venueName, imageUrl };
      }
    }
    if (source.config?.cardSelector) break;
    node = node.parent();
  }
  return null;
}

async function parseGenericCards(
  source: SourcePage,
  html: string,
  finalUrl: string,
): Promise<EventCandidate[]> {
  const $ = cheerio.load(html);
  const scope = mainScope($);
  const selector = source.config?.linkSelector ?? "a[href]";
  const seeds = new Map<string, GenericCardSeed>();
  for (const element of scope.find(selector).toArray()) {
    const seed = findGenericCard($, $(element), source, finalUrl);
    if (!seed) continue;
    const key = `${seed.sourceUrl}|${normalizeText(seed.title)}|${seed.date.startDate}`;
    if (!seeds.has(key)) seeds.set(key, seed);
    if (seeds.size >= source.max_event_links) break;
  }

  const output: EventCandidate[] = [];
  for (const seed of seeds.values()) {
    try {
      const candidate = await parseGenericDetail(source, seed.sourceUrl, seed.title, seed);
      if (candidate) {
        output.push({ ...candidate, parser: candidate.parser === "jsonld" ? "jsonld" : "generic-card" });
      }
    } catch {
      const defaultCurrency = source.config?.defaultCurrency ?? (source.country_code === "CZ" ? "CZK" : "EUR");
      const price = parsePrice(seed.text, defaultCurrency);
      const canceled = isCanceledText(`${seed.title} ${seed.text}`);
      const externalId = await sha256(`${source.source_code}|${seed.sourceUrl}|${seed.title}|${seed.date.startDate}`);
      output.push({
        sourceCode: source.source_code,
        sourcePageCode: source.code,
        sourceUrl: seed.sourceUrl,
        externalId,
        title: seed.title,
        summary: truncate(seed.text, 500),
        description: truncate(seed.text, 4000),
        startDate: seed.date.startDate,
        endDate: seed.date.endDate,
        allDay: seed.date.allDay,
        city: source.default_city,
        region: source.default_region,
        countryCode: source.country_code,
        venueName: seed.venueName ?? source.default_city,
        address: seed.venueName,
        imageUrl: seed.imageUrl,
        freeEntry: price.freeEntry,
        priceMin: price.priceMin,
        priceMax: price.priceMax,
        currency: price.currency,
        purchaseUrl: seed.sourceUrl,
        qualityScore: 76,
        warnings: canceled ? ["Podujatie je zrušené"] : ["Detail sa nepodarilo obohatiť; použité dáta z karty."],
        canceled,
        parser: "generic-card",
        raw: { parser: "generic-card-v4", cardText: truncate(seed.text, 1800) },
      });
    }
  }
  return output;
}

async function parseCitioDetail(
  source: SourcePage,
  sourceUrl: string,
  anchorTitle: string,
): Promise<EventCandidate | null> {
  const { html, finalUrl } = await fetchHtml(sourceUrl);
  const $ = cheerio.load(html);
  const jsonEvents: JsonObject[] = [];
  for (const root of extractJsonLd($)) walkJson(root, jsonEvents);
  for (const event of jsonEvents) {
    const candidate = await candidateFromJsonLd(event, source, finalUrl);
    if (candidate) return candidate;
  }

  const title = cleanAnchorTitle(anchorTitle);
  if (isBlockedTitle(title)) return null;
  const text = cleanedText($);
  const eventWindow = extractSectionWindow(text, title, ["Informácie", "Podobné", "Publikované"]);
  const date = parseHumanDateRange(eventWindow.slice(0, 500));
  if (!date.startDate) return null;
  const price = parsePrice(eventWindow);
  const canceled = isCanceledText(`${title} ${eventWindow}`);
  const imageUrl = findImage($, finalUrl);
  const locationMatch = text.match(/(?:Informácie\s+)?([^.!?]{2,100},\s*(?:Banská Bystrica|Kordíky))/i);
  const externalId = await sha256(`${source.source_code}|${finalUrl}|${title}|${date.startDate}`);
  let qualityScore = 75;
  if (imageUrl) qualityScore += 8;
  if (eventWindow.length > 120) qualityScore += 7;
  if (price.freeEntry || price.priceMin !== null) qualityScore += 5;
  if (source.default_city) qualityScore += 5;

  return {
    sourceCode: source.source_code,
    sourcePageCode: source.code,
    sourceUrl: finalUrl,
    externalId,
    title,
    summary: truncate(eventWindow, 500),
    description: truncate(eventWindow, 4000),
    startDate: date.startDate,
    endDate: date.endDate,
    allDay: date.allDay,
    city: source.default_city,
    region: source.default_region,
    countryCode: source.country_code,
    venueName: locationMatch ? collapseWhitespace(locationMatch[1]) : null,
    address: locationMatch ? collapseWhitespace(locationMatch[1]) : null,
    imageUrl,
    freeEntry: price.freeEntry,
    priceMin: price.priceMin,
    priceMax: price.priceMax,
    currency: price.currency,
    purchaseUrl: finalUrl,
    qualityScore: Math.min(100, qualityScore),
    warnings: canceled ? ["Podujatie je zrušené"] : [],
    canceled,
    parser: "citio-detail",
    raw: { parser: "citio-detail-v3", eventWindow: truncate(eventWindow, 1800) },
  };
}

function extractField(text: string, label: string, nextLabels: string[]) {
  const next = nextLabels.map((item) => item.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
  const escapedLabel = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`${escapedLabel}\\s*:\\s*(.*?)(?=\\s+(?:${next})\\s*:|$)`, "i");
  return getString(text.match(pattern)?.[1]);
}

async function parseWebygroupDetail(
  source: SourcePage,
  sourceUrl: string,
  anchorTitle: string,
): Promise<EventCandidate | null> {
  const { html, finalUrl } = await fetchHtml(sourceUrl);
  const $ = cheerio.load(html);
  const jsonEvents: JsonObject[] = [];
  for (const root of extractJsonLd($)) walkJson(root, jsonEvents);
  for (const event of jsonEvents) {
    const candidate = await candidateFromJsonLd(event, source, finalUrl);
    if (candidate) return candidate;
  }

  const text = cleanedText($);
  const title = cleanAnchorTitle(anchorTitle);
  if (!title || isBlockedTitle(title)) return null;
  const labels = ["Typ akcie", "Dátum", "Do", "Čas", "Miesto", "Vstupné", "Usporiadateľ", "Popis", "Fotogaléria", "Za obsah zodpovedá"];
  const dateText = extractField(text, "Dátum", labels.filter((item) => item !== "Dátum"));
  if (!dateText) return null;
  const endText = extractField(text, "Do", labels.filter((item) => item !== "Do"));
  const timeText = extractField(text, "Čas", labels.filter((item) => item !== "Čas"));
  const venueName = extractField(text, "Miesto", labels.filter((item) => item !== "Miesto"));
  const priceText = extractField(text, "Vstupné", labels.filter((item) => item !== "Vstupné"));
  const description = extractField(text, "Popis", ["Fotogaléria", "Za obsah zodpovedá", "Technický prevádzkovateľ"]);
  const date = parseWebygroupDateFields(dateText, endText, timeText);
  if (!date.startDate) return null;
  const price = parsePrice(priceText ?? "");
  const canceled = isCanceledText(`${title} ${description ?? ""}`);
  const imageUrl = findImage($, finalUrl);
  const externalId = await sha256(`${source.source_code}|${finalUrl}|${title}|${date.startDate}`);
  let qualityScore = 82;
  if (venueName) qualityScore += 5;
  if (imageUrl) qualityScore += 5;
  if (description && description.length > 100) qualityScore += 4;
  if (price.freeEntry || price.priceMin !== null) qualityScore += 4;

  return {
    sourceCode: source.source_code,
    sourcePageCode: source.code,
    sourceUrl: finalUrl,
    externalId,
    title,
    summary: truncate(description, 500),
    description: truncate(description, 4000),
    startDate: date.startDate,
    endDate: date.endDate,
    allDay: date.allDay,
    city: source.default_city,
    region: source.default_region,
    countryCode: source.country_code,
    venueName,
    address: null,
    imageUrl,
    freeEntry: price.freeEntry,
    priceMin: price.priceMin,
    priceMax: price.priceMax,
    currency: price.currency,
    purchaseUrl: finalUrl,
    qualityScore: Math.min(100, qualityScore),
    warnings: canceled ? ["Podujatie je zrušené"] : [],
    canceled,
    parser: "webygroup-detail",
    raw: {
      parser: "webygroup-detail-v3",
      dateText,
      endText,
      timeText,
      venueName,
      priceText,
    },
  };
}

function eventLinksInNode($: cheerio.CheerioAPI, node: cheerio.Cheerio<cheerio.AnyNode>) {
  const urls = new Set<string>();
  node.find('a[href*="/event/"]').each((_index: number, element: any) => {
    const href = $(element).attr("href");
    if (href) urls.add(href);
  });
  return urls.size;
}

function findTicketwareCard(
  $: cheerio.CheerioAPI,
  anchor: cheerio.Cheerio<cheerio.AnyNode>,
) {
  let node = anchor.parent();
  for (let depth = 0; depth < 7 && node.length; depth += 1) {
    const text = collapseWhitespace(node.text());
    if (text.length >= 20 && text.length <= 1800 && eventLinksInNode($, node) === 1) {
      const date = parseHumanDateRange(text, new Date().getFullYear());
      if (date.startDate) return { node, text, date };
    }
    node = node.parent();
  }
  return null;
}

async function parseTicketwareCards(
  source: SourcePage,
  html: string,
  finalUrl: string,
): Promise<EventCandidate[]> {
  const $ = cheerio.load(html);
  const output: EventCandidate[] = [];
  const seen = new Set<string>();
  const pattern = /^\/event\/\d+\/[^/?#]+\/?$/i;

  for (const element of mainScope($).find('a[href*="/event/"]').toArray()) {
    const anchor = $(element);
    const href = anchor.attr("href");
    if (!href) continue;
    const sourceUrl = absoluteUrl(href, finalUrl);
    if (!sourceUrl || !sameHost(sourceUrl, finalUrl)) continue;
    if (!pattern.test(new URL(sourceUrl).pathname)) continue;
    const title = cleanAnchorTitle(anchor.text());
    if (!title || isBlockedTitle(title)) continue;
    const card = findTicketwareCard($, anchor);
    if (!card) continue;
    const fingerprint = `${normalizeText(title)}|${card.date.startDate}|${sourceUrl}`;
    if (seen.has(fingerprint)) continue;
    seen.add(fingerprint);

    const price = parsePrice(card.text);
    const imageRaw = card.node.find("img[src]").first().attr("src");
    let imageUrl = imageRaw ? absoluteUrl(imageRaw, finalUrl) : null;
    let description = collapseWhitespace(card.text.replace(title, ""));
    let purchaseUrl: string | null = sourceUrl;

    try {
      const detail = await fetchHtml(sourceUrl);
      const detail$ = cheerio.load(detail.html);
      imageUrl = findImage(detail$, detail.finalUrl) ?? imageUrl;
      const detailText = cleanedText(detail$);
      const detailWindow = extractSectionWindow(
        detailText,
        title,
        ["Nenašli sa žiadne naplánované predstavenia", "Kde nás nájdete", "V prípade problémov so vstupenkami"],
      );
      if (detailWindow.length > description.length) description = detailWindow;
      purchaseUrl = detail.finalUrl;
    } catch {
      // Listing card is already a valid structured source. Detail enrichment is optional.
    }

    const canceled = isCanceledText(`${title} ${description}`);
    const externalId = await sha256(`${source.source_code}|${sourceUrl}|${title}|${card.date.startDate}`);
    let qualityScore = 82;
    if (imageUrl) qualityScore += 6;
    if (description.length > 80) qualityScore += 6;
    if (price.freeEntry || price.priceMin !== null) qualityScore += 6;

    output.push({
      sourceCode: source.source_code,
      sourcePageCode: source.code,
      sourceUrl,
      externalId,
      title,
      summary: truncate(description, 500),
      description: truncate(description, 4000),
      startDate: card.date.startDate,
      endDate: card.date.endDate,
      allDay: card.date.allDay,
      city: source.default_city,
      region: source.default_region,
      countryCode: source.country_code,
      venueName: source.default_city,
      address: null,
      imageUrl,
      freeEntry: price.freeEntry,
      priceMin: price.priceMin,
      priceMax: price.priceMax,
      currency: price.currency,
      purchaseUrl,
      qualityScore: Math.min(100, qualityScore),
      warnings: canceled ? ["Podujatie je zrušené"] : [],
      canceled,
      parser: "ticketware-card",
      raw: { parser: "ticketware-card-v3", cardText: truncate(card.text, 1800) },
    });
  }

  return output.slice(0, source.max_event_links);
}

function validateCandidate(candidate: EventCandidate, source: SourcePage): ValidationResult {
  if (isBlockedTitle(candidate.title)) return { accepted: false, reason: "blocked_title" };
  if (candidate.canceled) return { accepted: false, reason: "canceled" };
  if (!candidate.startDate) return { accepted: false, reason: "missing_date" };
  const start = new Date(candidate.startDate).getTime();
  const end = candidate.endDate ? new Date(candidate.endDate).getTime() : start;
  if (!Number.isFinite(start) || !Number.isFinite(end)) return { accepted: false, reason: "invalid_date" };
  const now = Date.now();
  if (end < now - 6 * 60 * 60 * 1000) return { accepted: false, reason: "past_event" };
  const maximumFutureDays = Number(source.config?.maximumFutureDays ?? 730);
  if (start > now + maximumFutureDays * DAY_MS) return { accepted: false, reason: "too_far_future" };
  if (!candidate.city && !candidate.venueName && !candidate.address) {
    return { accepted: false, reason: "missing_place" };
  }
  const minimumQuality = Number(source.config?.minimumQuality ?? 75);
  if (candidate.qualityScore < minimumQuality) return { accepted: false, reason: "low_quality" };
  return { accepted: true, reason: null };
}

function titleTokens(title: string) {
  return new Set(
    normalizeText(title)
      .replace(/\b20\d{2}\b/g, "")
      .split(" ")
      .filter((token) => token.length > 2),
  );
}

function jaccard(a: Set<string>, b: Set<string>) {
  const intersection = [...a].filter((item) => b.has(item)).length;
  const union = new Set([...a, ...b]).size;
  return union ? intersection / union : 0;
}

function sameEvent(a: EventCandidate, b: EventCandidate) {
  const startA = new Date(a.startDate ?? 0).getTime();
  const startB = new Date(b.startDate ?? 0).getTime();
  if (Math.abs(startA - startB) > 60 * 60 * 1000) return false;
  if (normalizeText(a.city ?? "") !== normalizeText(b.city ?? "")) return false;
  const titleA = normalizeText(a.title).replace(/\b20\d{2}\b/g, "").trim();
  const titleB = normalizeText(b.title).replace(/\b20\d{2}\b/g, "").trim();
  if (titleA === titleB) return true;
  const shorter = titleA.length <= titleB.length ? titleA : titleB;
  const longer = titleA.length > titleB.length ? titleA : titleB;
  if (shorter.length >= 10 && longer.startsWith(shorter)) return true;
  return jaccard(titleTokens(a.title), titleTokens(b.title)) >= 0.78;
}

function mergeCandidates(a: EventCandidate, b: EventCandidate) {
  const primary = a.qualityScore >= b.qualityScore ? a : b;
  const secondary = primary === a ? b : a;
  return {
    ...primary,
    title: primary.title.length >= secondary.title.length ? primary.title : secondary.title,
    summary: primary.summary ?? secondary.summary,
    description:
      (primary.description?.length ?? 0) >= (secondary.description?.length ?? 0)
        ? primary.description
        : secondary.description,
    endDate: primary.endDate ?? secondary.endDate,
    venueName: primary.venueName ?? secondary.venueName,
    address: primary.address ?? secondary.address,
    imageUrl: primary.imageUrl ?? secondary.imageUrl,
    freeEntry: primary.freeEntry || secondary.freeEntry,
    priceMin: primary.priceMin ?? secondary.priceMin,
    priceMax: primary.priceMax ?? secondary.priceMax,
    purchaseUrl: primary.purchaseUrl ?? secondary.purchaseUrl,
    qualityScore: Math.max(primary.qualityScore, secondary.qualityScore),
    warnings: [...new Set([...primary.warnings, ...secondary.warnings])],
  };
}

function dedupeCandidates(candidates: EventCandidate[]) {
  const output: EventCandidate[] = [];
  for (const candidate of candidates.sort((a, b) =>
    (a.startDate ?? "9999").localeCompare(b.startDate ?? "9999") ||
    b.qualityScore - a.qualityScore
  )) {
    const index = output.findIndex((existing) => sameEvent(existing, candidate));
    if (index < 0) output.push(candidate);
    else output[index] = mergeCandidates(output[index], candidate);
  }
  return output;
}

async function loadSources(
  supabase: ReturnType<typeof createClient>,
  sourceCodes: string[] | null,
  sourceGroup: string | null,
  includeDisabled: boolean,
) {
  const v2 = await supabase.rpc("catalog_list_source_pages_v2", {
    p_codes: sourceCodes,
    p_group_code: sourceGroup,
    p_include_disabled: includeDisabled,
  });
  if (!v2.error) return (v2.data ?? []) as SourcePage[];

  const v1 = await supabase.rpc("catalog_list_source_pages_v1", {
    p_codes: sourceCodes,
  });
  if (v1.error) throw new Error(`Načítanie zdrojov: ${v1.error.message}`);
  return (v1.data ?? []) as SourcePage[];
}

async function recordSourceRun(
  supabase: ReturnType<typeof createClient>,
  source: SourcePage,
  action: string,
  startedAt: string,
  durationMs: number,
  stats: JsonObject,
  errorMessage: string | null,
) {
  try {
    await supabase.rpc("catalog_record_source_run_v1", {
      p_source_page_code: source.code,
      p_action: action,
      p_started_at: startedAt,
      p_duration_ms: durationMs,
      p_success: !errorMessage,
      p_stats: stats,
      p_error_message: errorMessage,
    });
  } catch {
    // Health reporting migration may not be installed in older local databases.
  }
}

async function parseSource(source: SourcePage) {
  const listing = await fetchHtml(source.list_url);
  if (source.adapter === "ticketware_cards_v3") {
    return {
      discoveredLinks: 0,
      candidates: await parseTicketwareCards(source, listing.html, listing.finalUrl),
    };
  }
  if (source.adapter === "generic_cards_v4") {
    const candidates = await parseGenericCards(source, listing.html, listing.finalUrl);
    return { discoveredLinks: candidates.length, candidates };
  }

  const configured = safeRegex(source.config?.allowedPathRegex);
  const configuredUrl = safeRegex(source.config?.allowedUrlRegex);
  const fallback = source.adapter === "citio_detail_v3"
    ? /^\/podujatia\/[^/]+\/?$/i
    : /^\/akcia\/[^/]+\/mid\/\d+\/[.]html$/i;
  let links: Array<{ url: string; title: string }>;
  if (configuredUrl) {
    const $ = cheerio.load(listing.html);
    const found = new Map<string, string>();
    mainScope($).find("a[href]").each((_index: number, element: any) => {
      const href = $(element).attr("href");
      if (!href) return;
      const url = absoluteUrl(href, listing.finalUrl);
      if (!url || !allowedGenericUrl(source, url, listing.finalUrl) || !configuredUrl.test(url)) return;
      const title = cleanAnchorTitle($(element).text());
      if (!title || isBlockedTitle(title)) return;
      found.set(url, title);
    });
    links = [...found.entries()].slice(0, source.max_event_links).map(([url, title]) => ({ url, title }));
  } else {
    links = discoverExactLinks(
      listing.html,
      listing.finalUrl,
      configured ?? fallback,
      source.max_event_links,
    );
  }

  const candidates: EventCandidate[] = [];
  for (const link of links) {
    try {
      const candidate = source.adapter === "citio_detail_v3"
        ? await parseCitioDetail(source, link.url, link.title)
        : source.adapter === "generic_detail_v4"
        ? await parseGenericDetail(source, link.url, link.title)
        : await parseWebygroupDetail(source, link.url, link.title);
      if (candidate) candidates.push(candidate);
    } catch {
      // One broken detail must not stop the batch.
    }
  }
  return { discoveredLinks: links.length, candidates };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Použi POST." }, 405);

  try {
    const expectedToken = Deno.env.get("CATALOG_SYNC_TOKEN");
    const suppliedToken = request.headers.get("X-Sync-Token");
    if (!expectedToken || suppliedToken !== expectedToken) {
      return jsonResponse({ error: "Neplatné oprávnenie synchronizácie." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) throw new Error("Chýbajú Supabase serverové premenné.");

    const body = await request.json().catch(() => ({})) as JsonObject;
    const action = getString(body.action) ?? "preview";
    const sourceCodes = Array.isArray(body.sourceCodes)
      ? body.sourceCodes.filter((value): value is string => typeof value === "string")
      : null;
    const sourceGroup = getString(body.sourceGroup);
    const includeDisabled = body.includeDisabled === true;
    const maxEvents = Math.max(1, Math.min(300, Number(body.maxEvents ?? 120)));
    if (!['preview', 'sync'].includes(action)) {
      return jsonResponse({ error: "action musí byť preview alebo sync." }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const sources = await loadSources(supabase, sourceCodes, sourceGroup, includeDisabled);
    const accepted: EventCandidate[] = [];
    const rejected: Array<JsonObject> = [];
    const sourceStats: Record<string, JsonObject> = {};

    for (const source of sources) {
      const stats: JsonObject = {
        adapter: source.adapter,
        groupCode: source.group_code ?? null,
        listUrl: source.list_url,
        discoveredLinks: 0,
        parsedCandidates: 0,
        accepted: 0,
        rejected: 0,
        errors: [],
      };
      sourceStats[source.code] = stats;
      const sourceStartedAt = new Date().toISOString();
      const sourceStartedMs = Date.now();
      let sourceError: string | null = null;
      try {
        const parsed = await parseSource(source);
        stats.discoveredLinks = parsed.discoveredLinks;
        stats.parsedCandidates = parsed.candidates.length;
        for (const candidate of parsed.candidates) {
          const validation = validateCandidate(candidate, source);
          if (validation.accepted) {
            accepted.push(candidate);
            stats.accepted = Number(stats.accepted ?? 0) + 1;
          } else {
            rejected.push({
              title: candidate.title,
              sourcePageCode: source.code,
              sourceUrl: candidate.sourceUrl,
              startDate: candidate.startDate,
              reason: validation.reason ?? "unknown",
            });
            stats.rejected = Number(stats.rejected ?? 0) + 1;
          }
        }
      } catch (error) {
        sourceError = error instanceof Error ? error.message : String(error);
        (stats.errors as unknown[]).push({
          url: source.list_url,
          message: sourceError,
        });
      }
      stats.durationMs = Date.now() - sourceStartedMs;
      await recordSourceRun(
        supabase,
        source,
        action,
        sourceStartedAt,
        Number(stats.durationMs),
        stats,
        sourceError,
      );
    }

    const deduped = dedupeCandidates(accepted).slice(0, maxEvents);
    const rejectedReasons = rejected.reduce<Record<string, number>>((result, item) => {
      const reason = String(item.reason ?? "unknown");
      result[reason] = (result[reason] ?? 0) + 1;
      return result;
    }, {});

    if (action === "preview") {
      return jsonResponse({
        action,
        version: "municipal-parser-v4",
        sources: sourceStats,
        stats: {
          sourceCount: sources.length,
          acceptedBeforeDedupe: accepted.length,
          afterDedupe: deduped.length,
          duplicatesRemoved: accepted.length - deduped.length,
          rejected: rejected.length,
          rejectedReasons,
          quality80Plus: deduped.filter((candidate) => candidate.qualityScore >= 80).length,
        },
        preview: deduped,
        rejectedPreview: rejected.slice(0, 30),
        note: "Preview nič nezapísal. V4 používa zdrojové adaptéry, generické dátované karty a JSON-LD fallback.",
      });
    }

    const syncStats = { insertedOrUpdated: 0, errors: 0 };
    const synced: unknown[] = [];
    for (const candidate of deduped) {
      const { data, error } = await supabase.rpc("catalog_ingest_web_event_v1", {
        p_event: candidate,
      });
      if (error) {
        syncStats.errors += 1;
        synced.push({ title: candidate.title, error: error.message });
      } else {
        syncStats.insertedOrUpdated += 1;
        synced.push({ title: candidate.title, result: data });
      }
    }

    return jsonResponse({
      action,
      version: "municipal-parser-v4",
      sources: sourceStats,
      stats: syncStats,
      synced,
      note: "Udalosti boli uložené so stavom review. Zdrojové zdravie bolo aktualizované.",
    });
  } catch (error) {
    console.error("municipal-event-sync-v4:", error);
    return jsonResponse({
      error: error instanceof Error ? error.message : "Neznáma chyba.",
    }, 500);
  }
});
