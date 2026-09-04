$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = [System.Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Message)
{
	if (-not $Condition) { $script:errors.Add($Message) }
}

function Get-CsvHeader([string]$Path)
{
	$line = Get-Content -LiteralPath $Path -TotalCount 1
	return @($line.TrimStart([char]0xFEFF).Split(','))
}

$expectedHeaders = @{
	'UserRequest.csv' = @(
		'id','operational_status','status','ref','org_id','org_name','caller_id','caller_name',
		'team_id','team_id_friendlyname','agent_id','agent_name','impact','urgency','priority','origin',
		'request_type','start_date','end_date','last_update','assignment_date','resolution_date',
		'last_pending_date','sla_tto_passed','sla_ttr_passed','time_spent','resolution_code',
		'tto_escalation_deadline','ttr_escalation_deadline','service_name'
	)
	'TeamList.csv' = @('id','name')
	'FirstTeam_Affected.csv' = @('newvalue','objkey')
}

foreach ($locale in @('en-US','de-DE','nl-NL','fr-FR')) {
	foreach ($fileName in $expectedHeaders.Keys) {
		$fixture = Join-Path $root "tests/fixtures/$locale/$fileName"
		Assert-Contract (Test-Path -LiteralPath $fixture -PathType Leaf) "Missing $locale/$fileName fixture."
		if (Test-Path -LiteralPath $fixture -PathType Leaf) {
			$actual = Get-CsvHeader $fixture
			Assert-Contract (($actual -join ',') -ceq ($expectedHeaders[$fileName] -join ',')) "$locale/$fileName does not use the internal-code header contract."
		}
	}
}

$schemaPath = Join-Path $root 'tests/expected-schemas.json'
Assert-Contract (Test-Path -LiteralPath $schemaPath -PathType Leaf) 'Expected schema declaration is missing.'
if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
	$schemas = Get-Content -Raw -LiteralPath $schemaPath | ConvertFrom-Json
	foreach ($table in @('UserRequest','UserRequest_Period','TeamList','FirstTeam_Affected')) {
		$setName = $schemas.tables.$table
		$set = $schemas.schemaSets.$setName
		Assert-Contract ($null -ne $set) "Expected schema for $table is missing."
		if ($null -ne $set) {
			Assert-Contract ($set.names.Count -eq $set.mTypes.Count) "$table names and M types differ in length."
			Assert-Contract ($set.names.Count -eq $set.modelTypes.Count) "$table names and model types differ in length."
		}
	}
}

$mPath = Join-Path $root 'src/CombodoPowerBI/Mashup/Package/Formulas/Section1.m'
$mSource = Get-Content -Raw -LiteralPath $mPath
foreach ($token in @('BuildExportUrl','FetchQueryCsv','RequireColumns','ShapeUserRequest','format','csv','no_localize','Error.Record')) {
	Assert-Contract ($mSource.Contains($token)) "Power Query source is missing $token."
}
Assert-Contract (-not $mSource.Contains('Web.Page')) 'Power Query must not parse locale-sensitive HTML tables with Web.Page.'
foreach ($legacyPattern in @('\{\{"Ref",\s*type text','\{\{"id \(Primary Key\)"','\{\{"New value"','\{\{"object id"')) {
	Assert-Contract (-not [regex]::IsMatch($mSource, $legacyPattern)) "Power Query still treats a localized display header as source schema: $legacyPattern"
}

foreach ($errorFixture in @('login.html','invalid-query.html','missing-fields.csv','empty-user-request.csv','empty-team-list.csv')) {
	Assert-Contract (Test-Path -LiteralPath (Join-Path $root "tests/fixtures/errors/$errorFixture") -PathType Leaf) "Missing error fixture $errorFixture."
}
$scanFiles = @(Get-Item -LiteralPath $mPath) + @(Get-ChildItem -LiteralPath (Join-Path $root 'tests/fixtures') -File -Recurse)
foreach ($file in $scanFiles) {
	$content = Get-Content -Raw -LiteralPath $file.FullName
	Assert-Contract (-not [regex]::IsMatch($content, 'https?://(?:localhost|127\.|10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)', 'IgnoreCase')) "Private URL found in $($file.Name)."
}

$codeExtensions = @('.m','.ps1','.php','.py','.js','.ts','.tsx')
Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
	$codeExtensions -contains $_.Extension -and $_.FullName -notlike "$root\.cache\*"
} | ForEach-Object {
	$lineCount = @(Get-Content -LiteralPath $_.FullName).Count
	Assert-Contract ($lineCount -le 200) "$($_.FullName.Substring($root.Length + 1)) has $lineCount lines; maximum is 200."
}

if ($errors.Count -gt 0) {
	$errors | ForEach-Object { Write-Error $_ -ErrorAction Continue }
	throw "Template contract failed with $($errors.Count) error(s)."
}
Write-Output 'Template contract passed.'
