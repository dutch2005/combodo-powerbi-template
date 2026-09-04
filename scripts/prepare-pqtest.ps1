[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lock = Get-Content (Join-Path $root 'tools/power-query-sdk.lock.json') -Raw | ConvertFrom-Json
$cache = Join-Path $root ".cache/pq-sdk-tools-$($lock.version)"
$package = Join-Path $root ".cache/pq-sdk-tools-$($lock.version).nupkg"
$executable = Join-Path $cache 'tools/PQTest.exe'

if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
	[System.IO.Directory]::CreateDirectory((Split-Path $package -Parent)) | Out-Null
	Invoke-WebRequest -Uri $lock.packageUrl -OutFile $package
	$actual = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
	if ($actual -ne $lock.packageSha256) {
		throw "PQTest package checksum mismatch: expected $($lock.packageSha256), got $actual."
	}
	[System.IO.Compression.ZipFile]::ExtractToDirectory($package, $cache)
}

(Resolve-Path -LiteralPath $executable).Path
