let
    BuildExportUrl = __BUILD_EXPORT_URL__,
    QueryValue = (parts as record, name as text) as text => Text.From(Record.FieldOrDefault(parts[Query], name, "")),
    GuiUrl = BuildExportUrl("gui", "https://example.invalid/itop/pages/UI.php?operation=details&class=QueryOQL&id=26&foo=bar"),
    Gui = Uri.Parts(GuiUrl),
    GuiPass = Gui[Path] = "/itop/webservices/export-v2.php"
        and QueryValue(Gui, "query") = "26"
        and QueryValue(Gui, "foo") = "bar"
        and QueryValue(Gui, "format") = "csv"
        and QueryValue(Gui, "login_mode") = "basic"
        and QueryValue(Gui, "no_localize") = "1"
        and QueryValue(Gui, "date_format") = "Y-m-d H:i:s"
        and QueryValue(Gui, "charset") = "UTF-8"
        and QueryValue(Gui, "separator") = ","
        and not Record.HasFields(Gui[Query], {"operation", "class", "id"}),
    DirectUrl = BuildExportUrl("direct", "https://example.invalid/itop/webservices/export-v2.php?query=44&format=spreadsheet&login_mode=token&no_localize=0&date_format=d%2Fm%2FY&charset=ISO-8859-1&separator=%3B&arg_org=5"),
    Direct = Uri.Parts(DirectUrl),
    DirectPass = Direct[Path] = "/itop/webservices/export-v2.php"
        and QueryValue(Direct, "query") = "44"
        and QueryValue(Direct, "arg_org") = "5"
        and QueryValue(Direct, "format") = "csv"
        and QueryValue(Direct, "login_mode") = "basic"
        and QueryValue(Direct, "no_localize") = "1"
        and QueryValue(Direct, "date_format") = "Y-m-d H:i:s"
        and QueryValue(Direct, "charset") = "UTF-8"
        and QueryValue(Direct, "separator") = ",",
    CaseUrl = BuildExportUrl("case", "https://example.invalid/itop/pages/ui.PHP?CLASS=queryoql&ID=77"),
    Case = Uri.Parts(CaseUrl),
    CasePass = Case[Path] = "/itop/webservices/export-v2.php" and QueryValue(Case, "query") = "77",
    InvalidClass = try BuildExportUrl("invalid class", "https://example.invalid/itop/pages/UI.php?operation=details&class=Person&id=26"),
    MissingGuiId = try BuildExportUrl("missing GUI id", "https://example.invalid/itop/pages/UI.php?operation=details&class=QueryOQL"),
    MissingDirectId = try BuildExportUrl("missing direct id", "https://example.invalid/itop/webservices/export-v2.php?format=csv"),
    Results = #table(
        type table [Case = text, Passed = logical],
        {
            {"GUI details URL", GuiPass},
            {"direct export URL", DirectPass},
            {"case-insensitive GUI URL", CasePass},
            {"reject non-QueryOQL GUI URL", InvalidClass[HasError]},
            {"reject GUI URL without id", MissingGuiId[HasError]},
            {"reject export URL without query", MissingDirectId[HasError]}
        }
    ),
    Failed = Table.SelectRows(Results, each not [Passed])
in
    if Table.IsEmpty(Failed) then Results else error Error.Record("Test.Failure", "BuildExportUrl regression", Failed)
