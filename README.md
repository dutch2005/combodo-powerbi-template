# Reporting template for Power BI - Helpdesk view

This repository contains the source and release template for the iTop Helpdesk Power BI report. Version 1.1.0 keeps the existing English report pages and model while making data refresh independent of the iTop user's display language.

## Install version 1.1.0

1. Install **Reporting for PowerBI - Helpdesk view 1.1.0** in iTop first.
2. In iTop, open the Query Phrasebook and copy either the QueryOQL details URLs or the `export-v2.php` URLs for:
   - PowerBI - Integration - User Requests updated over the last 12 months
   - PowerBI - Integration - List teams' name - Combodo
   - PowerBI - Integration - List the first teams dispatched on Tickets updated over the last 12 months - Combodo (optional)
3. Open `artifacts/Combodo_PowerBI_Reporting_Template_1.1.0.pbit` in Power BI Desktop.
4. Enter the three URLs plus the iTop login and password when prompted.
5. When Power BI asks for web data-source credentials, select **Anonymous**. The template supplies the Basic authorization header itself.

For a details URL such as `/pages/UI.php?operation=details&class=QueryOQL&id=26`, the template automatically calls `/webservices/export-v2.php?...&query=26`. Existing export URLs remain supported. Both calendar tables extend from 2021 through the end of the current year at each refresh.

Treat 1.1.0 as a replacement template rather than an in-place conversion of a customized 1.0.x report. Reapply any private report customizations to a copy of 1.1.0.

## Language behavior

The template requests UTF-8 CSV with `no_localize=1` and a fixed date format. It selects stable iTop field codes such as `ref`, `id`, `newvalue`, and `objkey`, then maps them back to the unchanged report model.

This path works the same for every iTop-supported left-to-right account language; it is not limited to English, German, Dutch, or French. Those four locales have explicit sanitized fixtures. Report captions remain English. Right-to-left report presentation is not claimed.

## Troubleshooting

- **Invalid QueryOQL URL:** use either a QueryOQL details URL containing its `id` or an `export-v2.php` URL containing its `query` id.
- **HTML instead of CSV:** verify the account credentials and export permission; the response may be a login or error page.
- **HTTP error:** verify the iTop URL, saved-query identifier, access rights, and credentials.
- **Missing internal fields:** install extension 1.1.0 and make sure the URL points to its matching Query Phrasebook entry.
- **Malformed CSV or date/time:** verify that the response has not been rewritten by a proxy and that the URL is the original iTop export URL.

Errors name the failing query but never include the password or authorization value. The optional first-team URL can be left blank; it then produces an empty typed table without a web request.

For rollback, use the preserved 1.0.x artifact under `artifacts/legacy/`. That version retains the old language-sensitive behavior.

## Validation

Run the static locale and preservation gates:

```powershell
./tests/assert-contract.ps1
./tests/assert-model-parity.ps1
```

Run portable archive verification. It checks unique non-empty PBIT entries, the committed checksum, embedded Mashup and model expressions against source, and the 10-page/76-visual report layout:

```powershell
./scripts/verify-artifact.ps1 -Extractor Archive
```

CI also boots the digest-pinned pbi-tools Core 1.2.0 image, but Core cannot extract this current Desktop artifact and Core compilation omits `DataMashup` ([pbi-tools issue #16](https://github.com/pbi-tools/pbi-tools/issues/16)). Full source-to-artifact extraction and release builds therefore use the locked Desktop edition and Power BI Desktop 2.157.1354.0. pbi-tools 1.2.0 calls an older packaging overload, so the build wrapper applies a reviewed one-call compatibility patch ([pbi-tools issue #434](https://github.com/pbi-tools/pbi-tools/issues/434)) and verifies every binary hash before use.

After obtaining the locked pbi-tools Desktop executable, Mono.Cecil 0.11.5, and the matching Power BI Desktop `bin` directory, build with:

```powershell
./scripts/pbi-tools-desktop.ps1 -Action Compile `
  -Source 'src/CombodoPowerBI' `
  -Destination 'artifacts/Combodo_PowerBI_Reporting_Template_1.1.0.pbit' `
  -PbiInstallDir '<Power BI Desktop bin>' `
  -PbiToolsExe '<pbi-tools 1.2.0 Desktop exe>' `
  -MonoCecilDll '<Mono.Cecil 0.11.5 dll>'
```

Use the same three paths with `./scripts/verify-artifact.ps1 -Extractor Desktop` to re-extract the built PBIT and verify its Mashup, model, 10 pages, and 76 visuals against source.

`tools/pbi-tools.lock.json` records the reviewed versions and SHA-256 values. `artifacts/SHA256SUMS.txt` records the release artifact hash.

## Verification boundary

Automated CI checks statically validate the EN/DE/NL/FR fixture shapes, fixed internal headers and dates, presence of sanitized negative fixtures, source/model parity, archive structure, embedded Mashup/model parity, page count, visual count, and artifact checksum. Locked Desktop verification additionally re-extracts and compares the full report, model, and Mashup trees. Neither path executes the fixtures in the Power Query engine. A live refresh against a reachable iTop instance has not been performed in this repository environment; do not interpret the checks as proof of runtime transformations, production credentials, connectivity, or instance permissions.

The Query Phrasebook extension is maintained at [dutch2005/combodo-powerbi-integration](https://github.com/dutch2005/combodo-powerbi-integration).
