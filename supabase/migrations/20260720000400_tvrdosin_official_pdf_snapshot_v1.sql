-- Rodinny radar - Tvrdosin Official PDF Snapshot Adapter V1
-- The live HTML calendar currently contains no usable event rows.
-- Explicitly dated public/family events are curated from the official 2026 city PDF.
-- Cron stays disabled because this snapshot requires a controlled annual refresh.

begin;

insert into public.sources (
  code,
  display_name,
  source_type,
  website_url,
  trust_level,
  is_official,
  attribution_required,
  default_cache_ttl_seconds,
  active
)
values (
  'tvrdosin_events',
  'Mesto Tvrdošín - kalendár podujatí',
  'html',
  'https://www.tvrdosin.sk/aktualne/kalendar-akcii/',
  95,
  true,
  false,
  21600,
  true
)
on conflict (code) do update
set
  display_name = excluded.display_name,
  source_type = excluded.source_type,
  website_url = excluded.website_url,
  trust_level = excluded.trust_level,
  is_official = excluded.is_official,
  attribution_required = excluded.attribution_required,
  default_cache_ttl_seconds = excluded.default_cache_ttl_seconds,
  active = excluded.active,
  updated_at = now();

insert into private.source_pages (
  code,
  display_name,
  source_code,
  list_url,
  adapter,
  country_code,
  default_city,
  default_region,
  max_event_links,
  enabled,
  group_code,
  priority,
  cron_enabled,
  config
)
values (
  'tvrdosin-events',
  'Tvrdošín - oficiálny PDF kalendár 2026',
  'tvrdosin_events',
  'https://www.tvrdosin.sk/aktualne/kalendar-akcii/',
  'official_pdf_snapshot_v1',
  'SK',
  'Tvrdošín',
  'Žilinský kraj',
  60,
  true,
  'sk-za',
  20,
  false,
  jsonb_build_object(
    'minimumQuality', 80,
    'maximumFutureDays', 365,
    'defaultCurrency', 'EUR',
    'snapshotYear', 2026,
    'snapshotDocumentUrl', 'https://www.tvrdosin.sk/e_download.php?file=/data/editor/18sk_1.pdf&original=Kalend%C3%A1r%20podujat%C3%AD%20TS%202026%20web.pdf',
    'snapshotEventCount', 44,
    'snapshotEvents', $events$
[
  {
    "id": "2026-07-20-leto-s-cvc",
    "title": "Leto s CVČ",
    "summary": "Prímestský letný tábor pre deti základných škôl.",
    "startDate": "2026-07-20",
    "endDate": "2026-07-24",
    "venueName": "CVČ Tvrdošín",
    "address": "CVČ Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "CVČ Tvrdošín",
    "page": 15
  },
  {
    "id": "2026-07-26-folklorne-slavnosti-pod-osobitou",
    "title": "Folklórne slávnosti pod Osobitou a jarmok ľudových remesiel",
    "summary": "Folklórny festival a jarmok ľudových remesiel.",
    "startDate": "2026-07-26",
    "venueName": "Prírodný amfiteáter Oravice",
    "address": "Prírodný amfiteáter Oravice",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín",
    "page": 16
  },
  {
    "id": "2026-08-09-festival-netradicneho-ovocia",
    "title": "Festival netradičného ovocia",
    "summary": "Rodinný festival so zdravými jedlami, ovocím, tombolou, súťažami pre deti a divadelným vystúpením.",
    "startDate": "2026-08-09",
    "venueName": "Trojičné námestie",
    "address": "Trojičné námestie, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "OZ Misia mladých",
    "page": 16
  },
  {
    "id": "2026-08-18-dni-mesta",
    "title": "Dni mesta",
    "summary": "Kultúrne a športové podujatia mesta Tvrdošín.",
    "startDate": "2026-08-18",
    "endDate": "2026-08-23",
    "venueName": "Trojičné námestie",
    "address": "Trojičné námestie, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín",
    "page": 16
  },
  {
    "id": "2026-09-10-herne-popoludnie",
    "title": "Herné popoludnie",
    "summary": "Popoludnie pre deti základných a stredných škôl so spoločenskými hrami v knižnici.",
    "startDate": "2026-09-10",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 17
  },
  {
    "id": "2026-09-10-zapis-deti-do-zu-v-cvc",
    "title": "Zápis detí do záujmových útvarov v CVČ",
    "summary": "Zápis detí do záujmových útvarov CVČ na školský rok 2026/2027.",
    "startDate": "2026-09-10",
    "venueName": "CVČ Tvrdošín",
    "address": "CVČ Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "CVČ Tvrdošín",
    "page": 17
  },
  {
    "id": "2026-09-15-put-ku-skalke",
    "title": "Púť ku Skalke",
    "summary": "Svätá omša na pútnickom mieste Skalka.",
    "startDate": "2026-09-15",
    "venueName": "Skalka nad Medvedzím",
    "address": "Skalka nad Medvedzím, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín",
    "page": 17
  },
  {
    "id": "2026-09-20-koncert-v-drevenom-kostoliku",
    "title": "Koncert v drevenom kostolíku",
    "summary": "Hudobný program pri ukončení letnej sezóny.",
    "startDate": "2026-09-20",
    "startTime": "15:00",
    "venueName": "Drevený kostolík v Tvrdošíne",
    "address": "Drevený kostolík, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "ZUŠ Tvrdošín a Mesto Tvrdošín",
    "page": 17
  },
  {
    "id": "2026-09-21-vystava-ovocia-a-zeleniny",
    "title": "Výstava ovocia a zeleniny",
    "summary": "Výstava dopestovaných plodín z Tvrdošína.",
    "startDate": "2026-09-21",
    "endDate": "2026-09-25",
    "venueName": "Výstavná sála MsKS",
    "address": "Výstavná sála MsKS, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Záhradkársky zväz a Mesto Tvrdošín",
    "page": 17
  },
  {
    "id": "2026-09-22-caj-o-druhej",
    "title": "Čaj o druhej",
    "summary": "Čitateľský klub pri šálke čaju alebo kávy.",
    "startDate": "2026-09-22",
    "startTime": "14:00",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 17
  },
  {
    "id": "2026-09-25-michalsky-jarmok",
    "title": "Michalský jarmok",
    "summary": "Výročný jarmok s kultúrnym programom.",
    "startDate": "2026-09-25",
    "venueName": "Michalské námestie",
    "address": "Michalské námestie, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín",
    "page": 17
  },
  {
    "id": "2026-09-29-tvorive-dielne-farby-jesene",
    "title": "Tvorivé dielne – Farby jesene v knihách",
    "summary": "Tvorivé dielne pre deti prvého a druhého stupňa základných škôl.",
    "startDate": "2026-09-29",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 17
  },
  {
    "id": "2026-10-04-najkrajsia-tekvicka",
    "title": "Súťaž o najkrajšiu tekvičku",
    "summary": "Výstava tekvíc.",
    "startDate": "2026-10-04",
    "venueName": "CVČ Tvrdošín",
    "address": "CVČ Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "CVČ Tvrdošín",
    "page": 18
  },
  {
    "id": "2026-10-06-herne-popoludnie",
    "title": "Herné popoludnie",
    "summary": "Popoludnie pre deti základných a stredných škôl so spoločenskými hrami v knižnici.",
    "startDate": "2026-10-06",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 18
  },
  {
    "id": "2026-10-11-burza-zberatelov",
    "title": "Burza zberateľov",
    "summary": "Burza pre zberateľov a návštevníkov.",
    "startDate": "2026-10-11",
    "venueName": "Spoločenská sála Tvrdošín",
    "address": "Spoločenská sála, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín a Numizmatický krúžok",
    "page": 18
  },
  {
    "id": "2026-10-13-caj-o-druhej",
    "title": "Čaj o druhej",
    "summary": "Čitateľský klub pri šálke čaju alebo kávy.",
    "startDate": "2026-10-13",
    "startTime": "14:00",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 18
  },
  {
    "id": "2026-10-18-tanecny-workshop",
    "title": "Tanečný workshop",
    "summary": "Tanečný workshop pre deti CVČ.",
    "startDate": "2026-10-18",
    "venueName": "CVČ Tvrdošín",
    "address": "CVČ Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "CVČ Tvrdošín",
    "page": 18
  },
  {
    "id": "2026-10-20-tvorive-dielne-tajomstva-knih",
    "title": "Tvorivé dielne – Tajomstvá kníh",
    "summary": "Tvorivé dielne pre deti prvého a druhého stupňa základných škôl.",
    "startDate": "2026-10-20",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 18
  },
  {
    "id": "2026-10-22-ziacky-koncert",
    "title": "Žiacky koncert",
    "summary": "Koncert žiakov k úcte starším.",
    "startDate": "2026-10-22",
    "startTime": "16:00",
    "venueName": "Spoločenská sála na Medvedzí",
    "address": "Spoločenská sála na Medvedzí, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "ZUŠ Tvrdošín",
    "page": 18
  },
  {
    "id": "2026-10-29-pre-vsetkych-v-nebi",
    "title": "Pre všetkých v nebi",
    "summary": "Lampiónový sprievod pre rodiny s deťmi.",
    "startDate": "2026-10-29",
    "venueName": "Michalské námestie",
    "address": "Michalské námestie – Trojičné námestie – cintorín Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "CVČ Tvrdošín",
    "page": 18
  },
  {
    "id": "2026-11-01-odpustova-omsa",
    "title": "Odpustová svätá omša",
    "summary": "Odpustová svätá omša.",
    "startDate": "2026-11-01",
    "venueName": "Drevený gotický kostol Všetkých svätých",
    "address": "Drevený gotický kostol Všetkých svätých, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Rímskokatolícka farnosť Tvrdošín",
    "page": 19
  },
  {
    "id": "2026-11-02-odpustova-omsa",
    "title": "Odpustová svätá omša",
    "summary": "Odpustová svätá omša.",
    "startDate": "2026-11-02",
    "venueName": "Drevený gotický kostol Všetkých svätých",
    "address": "Drevený gotický kostol Všetkých svätých, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Rímskokatolícka farnosť Tvrdošín",
    "page": 19
  },
  {
    "id": "2026-11-03-herne-popoludnie",
    "title": "Herné popoludnie",
    "summary": "Popoludnie pre deti základných a stredných škôl so spoločenskými hrami v knižnici.",
    "startDate": "2026-11-03",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 19
  },
  {
    "id": "2026-11-10-caj-o-druhej",
    "title": "Čaj o druhej",
    "summary": "Čitateľský klub pri šálke čaju alebo kávy.",
    "startDate": "2026-11-10",
    "startTime": "14:00",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 19
  },
  {
    "id": "2026-11-11-den-cervenych-makov",
    "title": "Deň červených makov",
    "summary": "Spomienkové podujatie v mestskom parku.",
    "startDate": "2026-11-11",
    "venueName": "Mestský park",
    "address": "Mestský park, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Gymnázium a Spojená škola Tvrdošín",
    "page": 19
  },
  {
    "id": "2026-11-15-chramovy-koncert-liesek",
    "title": "Chrámový koncert",
    "summary": "Koncert ku cti svätej Cecílie.",
    "startDate": "2026-11-15",
    "startTime": "16:00",
    "venueName": "Kostol sv. Michala Archanjela",
    "address": "Kostol sv. Michala Archanjela, Liesek",
    "city": "Liesek",
    "organizer": "ZUŠ Tvrdošín",
    "page": 20
  },
  {
    "id": "2026-11-17-pietna-spomienka-frauwirth",
    "title": "Pietna spomienka na M. Frauwirtha",
    "summary": "Pietna spomienka v mestskom parku.",
    "startDate": "2026-11-17",
    "venueName": "Mestský park",
    "address": "Mestský park, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Gymnázium a Spojená škola Tvrdošín",
    "page": 20
  },
  {
    "id": "2026-11-22-chramovy-koncert-tvrdosin",
    "title": "Chrámový koncert",
    "summary": "Koncert ku cti svätej Cecílie.",
    "startDate": "2026-11-22",
    "startTime": "16:30",
    "venueName": "Kostol Najsvätejšej Trojice",
    "address": "Kostol Najsvätejšej Trojice, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "ZUŠ Tvrdošín, ZUŠ Námestovo a RKFÚ Tvrdošín",
    "page": 20
  },
  {
    "id": "2026-11-24-tvorive-dielne-kniha-ktora-zahreje",
    "title": "Tvorivé dielne – Kniha, ktorá zahreje",
    "summary": "Tvorivé dielne pre deti prvého a druhého stupňa základných škôl.",
    "startDate": "2026-11-24",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 20
  },
  {
    "id": "2026-11-26-moj-prvy-koncert-1530",
    "title": "Môj prvý koncert – 15:30",
    "summary": "Koncert žiakov prvého ročníka.",
    "startDate": "2026-11-26",
    "startTime": "15:30",
    "venueName": "Spoločenská sála na Medvedzí",
    "address": "Spoločenská sála na Medvedzí, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "ZUŠ Tvrdošín",
    "page": 20
  },
  {
    "id": "2026-11-26-moj-prvy-koncert-1630",
    "title": "Môj prvý koncert – 16:30",
    "summary": "Koncert žiakov prvého ročníka.",
    "startDate": "2026-11-26",
    "startTime": "16:30",
    "venueName": "Spoločenská sála na Medvedzí",
    "address": "Spoločenská sála na Medvedzí, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "ZUŠ Tvrdošín",
    "page": 20
  },
  {
    "id": "2026-12-01-tvoriva-zima",
    "title": "Tvorivá zima",
    "summary": "Tvorivé dielne pre deti prvého a druhého stupňa základných škôl počas decembra.",
    "startDate": "2026-12-01",
    "endDate": "2026-12-31",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 21
  },
  {
    "id": "2026-12-03-mikulasska-besiedka",
    "title": "Mikulášska besiedka",
    "summary": "Besiedka pre deti CVČ.",
    "startDate": "2026-12-03",
    "venueName": "CVČ Tvrdošín",
    "address": "CVČ Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Centrum voľného času Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-04-mikulas-v-nasom-meste",
    "title": "Mikuláš v našom meste",
    "summary": "Rozsvietenie mestského vianočného stromčeka a stretnutie s Mikulášom.",
    "startDate": "2026-12-04",
    "venueName": "Trojičné námestie",
    "address": "Trojičné námestie, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-05-sviatok-pribuznosti",
    "title": "Sviatok príbuznosti",
    "summary": "Celomestská akcia pre seniorov a zdravotne postihnutých občanov mesta.",
    "startDate": "2026-12-05",
    "venueName": "Mestská športová hala",
    "address": "Mestská športová hala, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-08-herne-popoludnie",
    "title": "Herné popoludnie",
    "summary": "Popoludnie pre deti základných a stredných škôl so spoločenskými hrami v knižnici.",
    "startDate": "2026-12-08",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 21
  },
  {
    "id": "2026-12-09-vianocna-chvilka",
    "title": "Vianočná chvíľka",
    "summary": "Vianočné vystúpenie detí z Centra voľného času.",
    "startDate": "2026-12-09",
    "venueName": "Veľká spoločenská sála Tvrdošín",
    "address": "Veľká spoločenská sála, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Centrum voľného času Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-15-caj-o-druhej",
    "title": "Čaj o druhej",
    "summary": "Čitateľský klub pri šálke čaju alebo kávy.",
    "startDate": "2026-12-15",
    "startTime": "14:00",
    "venueName": "Mestská knižnica",
    "address": "Mestská knižnica, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mestská knižnica",
    "page": 21
  },
  {
    "id": "2026-12-15-vianocny-koncert-liesek",
    "title": "Vianočný koncert",
    "summary": "Vianočný koncert žiakov ZUŠ Tvrdošín.",
    "startDate": "2026-12-15",
    "startTime": "16:00",
    "venueName": "ZŠ s MŠ Liesek",
    "address": "ZŠ s MŠ Liesek",
    "city": "Liesek",
    "organizer": "ZUŠ Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-16-vianocny-koncert-zuberec",
    "title": "Vianočný koncert",
    "summary": "Vianočný koncert žiakov ZUŠ Tvrdošín.",
    "startDate": "2026-12-16",
    "startTime": "16:00",
    "venueName": "ZŠ s MŠ Zuberec",
    "address": "ZŠ s MŠ Zuberec",
    "city": "Zuberec",
    "organizer": "ZUŠ Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-17-vianocny-koncert-medvedzie",
    "title": "Vianočný koncert",
    "summary": "Vianočný koncert žiakov ZUŠ Tvrdošín.",
    "startDate": "2026-12-17",
    "startTime": "17:00",
    "venueName": "Spoločenská sála na Medvedzí",
    "address": "Spoločenská sála na Medvedzí, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "ZUŠ Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-26-stefansky-vystup",
    "title": "Štefanský výstup na Tatliačku a Javorové",
    "summary": "Turistický prechod.",
    "startDate": "2026-12-26",
    "venueName": "Tatliačka a Javorové",
    "address": "Tatliačka a Javorové, Orava",
    "city": "Tvrdošín",
    "organizer": "Cykloturistický klub Tvrdošín – Medvedzie",
    "page": 22
  },
  {
    "id": "2026-12-31-silvester-2026",
    "title": "Silvester 2026",
    "summary": "Stretnutie na Skalke a ohňostroj.",
    "startDate": "2026-12-31",
    "venueName": "Skalka nad Medvedzím",
    "address": "Skalka nad Medvedzím, Tvrdošín",
    "city": "Tvrdošín",
    "organizer": "Mesto Tvrdošín",
    "page": 21
  },
  {
    "id": "2026-12-31-silvestrovsky-vystup",
    "title": "Silvestrovský výstup na Choč – Javor – Tatliačku",
    "summary": "Silvestrovský turistický výstup.",
    "startDate": "2026-12-31",
    "venueName": "Choč – Javor – Tatliačka",
    "address": "Choč – Javor – Tatliačka, Orava",
    "city": "Tvrdošín",
    "organizer": "Cykloturistický klub Tvrdošín – Medvedzie",
    "page": 22
  }
]
$events$::jsonb,
    'detailParser', 'tvrdosin-official-pdf-snapshot-v1',
    'refreshPolicy', 'manual-annual-review'
  )
)
on conflict (code) do update
set
  display_name = excluded.display_name,
  source_code = excluded.source_code,
  list_url = excluded.list_url,
  adapter = excluded.adapter,
  country_code = excluded.country_code,
  default_city = excluded.default_city,
  default_region = excluded.default_region,
  max_event_links = excluded.max_event_links,
  enabled = excluded.enabled,
  group_code = excluded.group_code,
  priority = excluded.priority,
  cron_enabled = excluded.cron_enabled,
  config = excluded.config,
  updated_at = now();

insert into private.schema_versions (
  version,
  description
)
values (
  '2026-07-20-tvrdosin-official-pdf-snapshot-v1',
  'Tvrdošín official 2026 PDF snapshot adapter with 44 explicitly dated events'
)
on conflict (version) do nothing;

commit;
