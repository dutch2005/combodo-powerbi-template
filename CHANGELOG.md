# Changelog

## 1.1.1 - 2026-09-05

- Restored the correct yearly team measure comparison from the original calendar-fix work.
- Removed the two stale 2022 slicer filters and the cached 2022 resolution-year selection.
- Added direct regression checks for the DAX expression and both affected slicers.
- Made the longstanding root PBIT byte-identical to canonical 1.1.1 and removed the superseded defective 1.1.0 binary.
- Extended portable artifact verification to inspect the embedded measure and slicer state.
- Coordinates with `combodo-powerbi-integration` extension 1.1.1.

## 1.1.0 - 2026-09-04

- Replaced locale-sensitive HTML table parsing with UTF-8 CSV ingestion using stable iTop internal field codes.
- Added fixed export options for non-localized values and `Y-m-d H:i:s` dates.
- Added automatic conversion from QueryOQL GUI details URLs to the matching `export-v2.php` CSV endpoint.
- Replaced the expired 2024 calendar limit with an end-of-current-year value evaluated at refresh.
- Preserved all 10 report pages, 76 visuals, model tables, measures, relationships, parameters, and canonical output columns.
- Added clear errors for blank parameters, HTTP failures, login/error HTML, malformed CSV, invalid dates, and missing fields without exposing credentials.
- Added sanitized English, German, Dutch, and French contract fixtures. Every other iTop-supported left-to-right account language follows the same internal-code path; report captions remain English.
- Made the optional first-team query return an empty typed table without an HTTP request when its URL is blank.
- Added deterministic artifact checks and retained the original 1.0.x PBIT for rollback.
- Coordinates with `combodo-powerbi-integration` extension 1.1.0.

Live refresh against a reachable iTop instance was not available during automated validation and is not claimed.
