# Changelog

## 1.1.0 - 2026-09-04

- Replaced locale-sensitive HTML table parsing with UTF-8 CSV ingestion using stable iTop internal field codes.
- Added fixed export options for non-localized values and `Y-m-d H:i:s` dates.
- Preserved all 10 report pages, 76 visuals, model tables, measures, relationships, parameters, and canonical output columns.
- Added clear errors for blank parameters, HTTP failures, login/error HTML, malformed CSV, invalid dates, and missing fields without exposing credentials.
- Added sanitized English, German, Dutch, and French contract fixtures. Every other iTop-supported left-to-right account language follows the same internal-code path; report captions remain English.
- Made the optional first-team query return an empty typed table without an HTTP request when its URL is blank.
- Added deterministic artifact checks and retained the original 1.0.x PBIT for rollback.
- Coordinates with `combodo-powerbi-integration` extension 1.1.0.

Live refresh against a reachable iTop instance was not available during automated validation and is not claimed.
