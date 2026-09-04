[CmdletBinding()]
param([Parameter(Mandatory)][string]$PqTestExe)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = [System.IO.File]::ReadAllText((Join-Path $root 'src/CombodoPowerBI/Mashup/Package/Formulas/Section1.m'))
$match = [regex]::Match($source, '(?ms)shared BuildExportUrl\s*=\s*(.*?);\s*shared FetchQueryCsv')
if (-not $match.Success) { throw 'Unable to extract BuildExportUrl from production Mashup source.' }

$template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'power-query/BuildExportUrl.query.pq'))
if (-not $template.Contains('__BUILD_EXPORT_URL__')) { throw 'Power Query test placeholder is missing.' }
$query = $template.Replace('__BUILD_EXPORT_URL__', $match.Groups[1].Value.Trim())
$temporaryRoot = Join-Path $root '.cache/power-query-tests'
$temporary = Join-Path $temporaryRoot ([guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($temporary) | Out-Null
try {
	$queryPath = Join-Path $temporary 'BuildExportUrl.query.pq'
	[System.IO.File]::WriteAllText($queryPath, $query, [System.Text.UTF8Encoding]::new($false))
	$json = & (Resolve-Path -LiteralPath $PqTestExe) run-test --queryFile $queryPath
	if ($LASTEXITCODE -ne 0) { throw "Power Query behavior tests failed with exit code $LASTEXITCODE." }
	$result = $json | ConvertFrom-Json
	if ($result.Status -ne 'Passed' -or $result.RowCount -ne 6) {
		throw "Power Query returned unexpected results: status=$($result.Status), rows=$($result.RowCount)."
	}
	$failed = @($result.Output | Where-Object { $_.Passed -ne $true })
	if ($failed.Count -ne 0) { throw "Power Query reported $($failed.Count) failing behavior case(s)." }
} finally {
	Remove-Item -LiteralPath $temporary -Recurse -Force
}
Write-Output 'PASS: BuildExportUrl behavior executed by Microsoft Power Query.'
