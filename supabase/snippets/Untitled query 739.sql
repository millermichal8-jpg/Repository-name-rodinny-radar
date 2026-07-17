select
  'sources' as object_name,
  count(*) as row_count
from public.sources

union all

select
  'categories',
  count(*)
from public.categories

union all

select
  'connectors',
  count(*)
from private.source_connectors

union all

select
  'schema_version',
  count(*)
from private.schema_versions
where version = '2026-07-15-catalog-v2';