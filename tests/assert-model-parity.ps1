$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'src/CombodoPowerBI'
$baseline = Get-Content -Raw -LiteralPath (Join-Path $root 'tests/model-baseline.json') | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

$groups = @{
	Report = @('Report','StaticResources','DiagramLayout.json','ReportMetadata.json','ReportSettings.json')
	Model = @('Model')
	MashupSupport = @('Mashup/Package/Config','Mashup/Package/Content','Mashup/Package/Resources','Mashup/Package.xml','Mashup/permissions.json')
}
$errors = [System.Collections.Generic.List[string]]::new()
foreach ($name in $groups.Keys) {
	$actual = if ($name -eq 'Model') { Get-ModelStructureFingerprint (Join-Path $project 'Model') } else { Get-TreeFingerprint $project $groups[$name] }
	$expected = $baseline.$name
	if ($actual.count -ne $expected.count -or $actual.sha256 -cne $expected.sha256) {
		$errors.Add("$name changed outside the permitted Mashup expression and project metadata files.")
	}
}

$schemas = Get-Content -Raw -LiteralPath (Join-Path $root 'tests/expected-schemas.json') | ConvertFrom-Json
foreach ($tableName in @('UserRequest','UserRequest_Period','TeamList','FirstTeam_Affected')) {
	$tablePath = Join-Path $project "Model/tables/$tableName.tmdl"
	$sourceColumns = @(Select-String -LiteralPath $tablePath -Pattern '^\t\tsourceColumn: (.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
	$schemaName = $schemas.tables.$tableName
	$expectedNames = @($schemas.schemaSets.$schemaName.names)
	if (($sourceColumns -join '|') -cne ($expectedNames -join '|')) {
		$errors.Add("$tableName output columns differ from the 1.0.x model schema.")
	}
}

if ($errors.Count -gt 0) {
	$errors | ForEach-Object { Write-Error $_ -ErrorAction Continue }
	throw "Model parity failed with $($errors.Count) error(s)."
}
Write-Output 'Model parity passed.'
