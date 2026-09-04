section Section1;

shared UserRequest = let
    #"UserName"=user_login,
    #"Password"=user_password,
    #"Header" = Binary.ToText(Text.ToBinary(#"UserName"&":" & #"Password")),
    #"BaseURL" = url_user_request_itop,
    Source = Web.Page(Web.Contents(#"BaseURL", [Headers=[Authorization="Basic " & #"Header"]])),
    Data0 = Source{0}[Data],
    #"En-têtes promus" = Table.PromoteHeaders(Data0, [PromoteAllScalars=true]),
     #"Type modifié" = Table.TransformColumnTypes(#"En-têtes promus",{{"Ref", type text}}),
     #"Type modifié1" = Table.TransformColumnTypes(#"Type modifié",{{"Resolution date (date)", type date}, {"Assignment date (date)", type date}, {"Start date (date)", type date}, {"Start date (time)", type time}, {"End date (date)", type date}, {"End date (time)", type time}, {"Last update (date)", type date}, {"Last update (time)", type time}, {"Assignment date (time)", type time}, {"Resolution date (time)", type time}, {"Last pending date (date)", type date}, {"Last pending date (time)", type time}, {"TTO Deadline", type datetime}, {"TTR Deadline", type datetime}, {"Resolution delay", Int64.Type}}),
    #"Colonnes renommées" = Table.RenameColumns(#"Type modifié1",{{"Team_1", "Team_Name"}}),
    #"Valeur remplacée" = Table.ReplaceValue(#"Colonnes renommées",null,0,Replacer.ReplaceValue,{"Resolution delay"})
in
    #"Valeur remplacée";

shared UserRequest_Period = let
    #"UserName"=user_login,
    #"Password"=user_password,
    #"Header" = Binary.ToText(Text.ToBinary(#"UserName"&":" & #"Password")),
    #"BaseURL" = url_user_request_itop,
    Source = Web.Page(Web.Contents(#"BaseURL", [Headers=[Authorization="Basic " & #"Header"]])),
    Data0 = Source{0}[Data],
    #"En-têtes promus" = Table.PromoteHeaders(Data0, [PromoteAllScalars=true]),
     #"Type modifié" = Table.TransformColumnTypes(#"En-têtes promus",{{"Ref", type text}}),
     #"Type modifié1" = Table.TransformColumnTypes(#"Type modifié",{{"Resolution date (date)", type date}, {"Assignment date (date)", type date}, {"Start date (date)", type date}, {"Start date (time)", type time}, {"End date (date)", type date}, {"End date (time)", type time}, {"Last update (date)", type date}, {"Last update (time)", type time}, {"Assignment date (time)", type time}, {"Resolution date (time)", type time}, {"Last pending date (date)", type date}, {"Last pending date (time)", type time}, {"TTO Deadline", type datetime}, {"TTR Deadline", type datetime}, {"Resolution delay", Int64.Type}}),
    #"Colonnes renommées" = Table.RenameColumns(#"Type modifié1",{{"Team_1", "Team_Name"}}),
    #"Valeur remplacée" = Table.ReplaceValue(#"Colonnes renommées",null,0,Replacer.ReplaceValue,{"Resolution delay"})
in
    #"Valeur remplacée";

shared TeamList = let
    #"UserName" = user_login,
    #"Password" = user_password,
    #"Header" = Binary.ToText(Text.ToBinary(#"UserName"&":" & #"Password")),
    #"BaseURL" = url_list_team_name_itop,
    Source = Web.Page(Web.Contents(#"BaseURL", [Headers=[Authorization="Basic " & #"Header"]])),
    Data0 = Source{0}[Data],
    #"En-têtes promus" = Table.PromoteHeaders(Data0, [PromoteAllScalars=true]),
    #"Type modifié" = Table.TransformColumnTypes(#"En-têtes promus",{{"id (Primary Key)", Int64.Type}, {"Name", type text}})
in
    #"Type modifié";

shared Requête1 = (StartDate as date, EndDate as date, optional Culture as nullable text) as table =>

let
    DayCount = Duration.Days(Duration.From(EndDate - StartDate)) + 1,
    Source = List.Dates(StartDate,DayCount,#duration(1,0,0,0)),
    TableFromList = Table.FromList(Source, Splitter.SplitByNothing()),    
    ChangedType = Table.TransformColumnTypes(TableFromList,{{"Column1", type date}}),
    RenamedColumns = Table.RenameColumns(ChangedType,{{"Column1", "Date"}}),
    InsertYearKey = Table.AddColumn(RenamedColumns, "YearKey", each Date.Year([Date])),
    InsertYear = Table.AddColumn(InsertYearKey, "Year", each (Number.ToText([YearKey])), type text),
    InsertQuarterKey = Table.AddColumn(InsertYear, "QuarterKey", each (([YearKey] * 10) + Date.QuarterOfYear([Date]))),
    InsertQuarter = Table.AddColumn(InsertQuarterKey, "Quarter", each (Number.ToText([YearKey]) & "-Q" & Number.ToText(Date.QuarterOfYear([Date]))), type text),
    InsertMonthKey = Table.AddColumn(InsertQuarter, "MonthKey", each (([YearKey] * 100) + Date.Month([Date]))),
    InsertMonth = Table.AddColumn(InsertMonthKey, "Month", each (Number.ToText([YearKey]) & "-" & Date.ToText([Date], "MMM", Culture)), type text),
    InsertDateKey = Table.AddColumn(InsertMonth, "DateKey", each (([YearKey] * 10000) + (Date.Month([Date]) * 100) + Date.Day([Date]))),
    InsertDay = Table.AddColumn(InsertDateKey, "Day", each Date.ToText([Date], "yyyy-MMM-dd", Culture), type text),
    SetNumericColumns = Table.TransformColumnTypes(InsertDay, {{"DateKey", Int64.Type}, {"MonthKey", Int64.Type}, {"QuarterKey", Int64.Type}, {"YearKey", Int64.Type}}),
    DateTable = Table.ReorderColumns(SetNumericColumns, {"DateKey", "Date", "Day", "MonthKey", "Month", "QuarterKey", "Quarter", "YearKey", "Year"})
  in
    DateTable;

shared Calendrier_ResolutionDate = let
    Source = Requête1(#date(2021, 1, 1), #date(2024, 12, 31), null)
in
    Source;

shared Calendrier = let
    Source = Requête1(#date(2021, 1, 1), #date(2024, 12, 31), null)
in
    Source;

shared Mesures = let
    Source = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("i44FAA==", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [#"Colonne 1" = _t]),
    #"Type modifié" = Table.TransformColumnTypes(Source,{{"Colonne 1", type text}}),
    #"Colonnes supprimées" = Table.RemoveColumns(#"Type modifié",{"Colonne 1"})
in
    #"Colonnes supprimées";

shared TableMesures = let
    Source = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("i44FAA==", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [#"Colonne 1" = _t]),
    #"Type modifié" = Table.TransformColumnTypes(Source,{{"Colonne 1", type text}}),
    #"Colonnes supprimées" = Table.RemoveColumns(#"Type modifié",{"Colonne 1"})
in
    #"Colonnes supprimées";

shared FirstTeam_Affected = let
    FirstTeam_Affected_Init = if url_list_first_team_dispatched_itop <> null
    then { let    
    #"UserName"=user_login,
    #"Password"=user_password,
    #"Header" = Binary.ToText(Text.ToBinary(#"UserName"&":" & #"Password")),
    #"BaseURL" = url_list_first_team_dispatched_itop, 
    Source = Web.Page(Web.Contents(#"BaseURL", [Headers=[Authorization="Basic " & #"Header"]])),
    Data0 = Source{0}[Data],
    #"En-têtes promus" = Table.PromoteHeaders(Data0, [PromoteAllScalars=true]),
    #"Type modifié" = Table.TransformColumnTypes(#"En-têtes promus",{{"New value", Int64.Type}, {"object id", Int64.Type}}),
    #"Colonnes renommées" = Table.RenameColumns(#"Type modifié",{{"New value", "FirstTeam_affected_id"}, {"object id", "UserRequest_id"}}),
    #"Userrequest unique" = Table.Distinct(#"Colonnes renommées","UserRequest_id")
    in
    #"Userrequest unique"
    }
    else { let
    Source = #table(  
    type table [UserRequest_id = Int64.Type, FirstTeam_affected_id = Int64.Type],   
        {   
              {1, 1}
        }  
    )  
    in
    Source
    },
    FirstTeam_Affected = FirstTeam_Affected_Init{0}
in
    FirstTeam_Affected;

[ Description = "iTop user login" ]
shared user_login = null meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true];

[ Description = "iTop user password" ]
shared user_password = null meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true];

[ Description = "URL of iTop query#(lf)PowerBI - Integration - User Requests updated over the last 12 months" ]
shared url_user_request_itop = null meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true];

[ Description = "URL of iTop query#(lf)PowerBI - Integration - List teams' name - Combodo" ]
shared url_list_team_name_itop = null meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true];

[ Description = "URL of iTop query#(lf)PowerBI - Integration - List the first teams dispatched on Tickets updated over the last 12 months - Combodo" ]
shared url_list_first_team_dispatched_itop = null meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=false];