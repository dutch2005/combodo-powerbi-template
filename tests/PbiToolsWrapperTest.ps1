$ErrorActionPreference = 'Stop'

$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskWrapper = Join-Path $taskRoot 'scripts/pbi-tools.ps1'
$taskLock = Join-Path $taskRoot 'tools/pbi-tools.lock.json'

if (-not (Test-Path -LiteralPath $taskWrapper -PathType Leaf)) {
	throw 'pbi-tools wrapper is missing.'
}
if (-not (Test-Path -LiteralPath $taskLock -PathType Leaf)) {
	throw 'pbi-tools lock file is missing.'
}

$taskToolInfo = & $taskWrapper -Action Info
if ($LASTEXITCODE -ne 0 -or ($taskToolInfo -join "`n") -notmatch '1\.2\.0') {
	throw 'Pinned pbi-tools 1.2.0 did not run successfully.'
}

$taskRejected = $false
try {
	& $taskWrapper -Action Extract -Source '..\outside.pbit' -Destination 'src/out'
} catch {
	$taskRejected = $_.Exception.Message -match 'outside the repository'
}
if (-not $taskRejected) {
	throw 'Wrapper must reject paths outside the repository.'
}

Write-Output 'PASS: pinned pbi-tools wrapper and path guard'
