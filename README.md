# Reporting template for Power BI - Helpdesk view

This repository contains the source and release template for the iTop Helpdesk Power BI report. Version 1.1.0 keeps the existing English report pages and model while making data refresh independent of the iTop user's display language.

## Install version 1.1.0

1. Install **Reporting for PowerBI - Helpdesk view 1.1.0** in iTop first.
2. In iTop, open the Query Phrasebook and copy the export URLs for:
   - PowerBI - Integration - User Requests updated over the last 12 months
   - PowerBI - Integration - List teams' name - Combodo
   - PowerBI - Integration - List the first teams dispatched on Tickets updated over the last 12 months - Combodo (optional)
3. Open `artifacts/Combodo_PowerBI_Reporting_Template_1.1.0.pbit` in Power BI Desktop.
4. Enter the three URLs plus the iTop login and password when prompted.
5. When Power BI asks for web data-source credentials, select **Anonymous**. The template supplies the Basic authorization header itself.

Treat 1.1.0 as a replacement template rather than an in-place conversion of a customized 1.0.x report. Reapply any private report customizations to a copy of 1.1.0.

## Language behavior

The template requests UTF-8 CSV with `no_localize=1` and a fixed date format. It selects stable iTop field codes such as `ref`, `id`, `newvalue`, and `objkey`, then maps them back to the unchanged report model.

This path works the same for every iTop-supported left-to-right account language; it is not limited to English, German, Dutch, or French. Those four locales have explicit sanitized fixtures. Report captions remain English. Right-to-left report presentation is not claimed.

## Troubleshooting

- **HTML instead of CSV:** the URL may point to a login or error page. Recopy the Query Phrasebook URL and verify the account credentials and export permission.
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

Run full artifact verification with Docker. The wrapper uses the digest-pinned pbi-tools Core 1.2.0 image and re-extracts the committed PBIT to prove that its Mashup, model, pages, and 76 visuals match source:

```powershell
./scripts/verify-artifact.ps1
```

The Core image can verify/extract this artifact, but it cannot safely create it because Core compilation omits `DataMashup` ([pbi-tools issue #16](https://github.com/pbi-tools/pbi-tools/issues/16)). Release builds therefore use the locked Desktop edition and Power BI Desktop 2.157.1354.0. pbi-tools 1.2.0 calls an older packaging overload, so the build wrapper applies a reviewed one-call compatibility patch ([pbi-tools issue #434](https://github.com/pbi-tools/pbi-tools/issues/434)) and verifies every binary hash before use.

After obtaining the locked pbi-tools Desktop executable, Mono.Cecil 0.11.5, and the matching Power BI Desktop `bin` directory, build with:

```powershell
./scripts/pbi-tools-desktop.ps1 -Action Compile `
  -Source 'src/CombodoPowerBI' `
  -Destination 'artifacts/Combodo_PowerBI_Reporting_Template_1.1.0.pbit' `
  -PbiInstallDir '<Power BI Desktop bin>' `
  -PbiToolsExe '<pbi-tools 1.2.0 Desktop exe>' `
  -MonoCecilDll '<Mono.Cecil 0.11.5 dll>'
```

`tools/pbi-tools.lock.json` records the reviewed versions and SHA-256 values. `artifacts/SHA256SUMS.txt` records the release artifact hash.

## Verification boundary

Automated checks cover the EN/DE/NL/FR fixtures, fixed internal headers and dates, negative response contracts, source/model parity, binary Mashup parity, page count, visual count, and artifact checksum. A live refresh against a reachable iTop instance has not been performed in this repository environment; do not interpret the automated checks as proof of production credentials, connectivity, or instance permissions.

The Query Phrasebook extension is maintained at [dutch2005/combodo-powerbi-integration](https://github.com/dutch2005/combodo-powerbi-integration).
