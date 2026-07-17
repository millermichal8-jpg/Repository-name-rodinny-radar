# Municipal Event Quality V2

This patch replaces the first municipal parser with a stricter version.

Changes:
- strict detail URL patterns per platform,
- future/ongoing event filter,
- canceled-event rejection,
- navigation/footer title blocklist,
- direct card parsing for Webygroup calendars,
- better numeric and Slovak/Czech month date ranges,
- minimum quality score per source,
- clean accepted/rejected preview,
- basic deduplication by normalized title, date and city.

The preview action does not write to the catalog.
