[CmdletBinding()]
param(
	[Parameter(Mandatory)][ValidateSet('Info','Extract','Compile')][string]$Action,
	[string]$Source,
	[string]$Destination,
	[Parameter(Mandatory)][string]$PbiInstallDir,
	[Parameter(Mandatory)][string]$PbiToolsExe,
	[Parameter(Mandatory)][string]$MonoCecilDll
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rootPrefix = $root.TrimEnd('\') + '\'
$lock = Get-Content -Raw -LiteralPath (Join-Path $root 'tools/pbi-tools.lock.json') | ConvertFrom-Json

function Resolve-RepositoryPath([string]$RelativePath, [bool]$MustExist)
{
	if ([System.IO.Path]::IsPathRooted($RelativePath)) { throw "Path must be repository-relative: $RelativePath" }
	$fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $RelativePath))
	if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside repository: $RelativePath" }
	if ($MustExist -and -not (Test-Path -LiteralPath $fullPath)) { throw "Required path does not exist: $RelativePath" }
	return $fullPath
}

$packagingDll = Join-Path (Resolve-Path -LiteralPath $PbiInstallDir) 'Microsoft.PowerBI.Packaging.dll'
$inputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PbiToolsExe).Hash
$packagingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagingDll).Hash
if ($inputHash -cne $lock.desktopBuild.pbiToolsExeSha256) { throw 'Unexpected pbi-tools executable; use locked Desktop edition 1.2.0.' }
if ($packagingHash -cne $lock.desktopBuild.packagingDllSha256) { throw 'Unexpected Power BI Packaging library; update and review the lock before building.' }

$patchedDirectory = Join-Path $root '.cache/pbi-tools-desktop'
$patchedExe = Join-Path $patchedDirectory 'pbi-tools.exe'
& (Join-Path $PSScriptRoot 'patch-pbi-tools.ps1') -InputExe $PbiToolsExe -PackagingDll $packagingDll -MonoCecilDll $MonoCecilDll -ExpectedMonoCecilSha256 $lock.desktopBuild.monoCecilSha256 -OutputExe $patchedExe
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patchedExe).Hash -cne $lock.desktopBuild.patchedExeSha256) { throw 'Patched pbi-tools hash does not match the reviewed build.' }
Copy-Item -LiteralPath ([System.IO.Path]::ChangeExtension($PbiToolsExe, '.exe.config')) -Destination ([System.IO.Path]::ChangeExtension($patchedExe, '.exe.config')) -Force
$env:PBITOOLS_PbiInstallDir = (Resolve-Path -LiteralPath $PbiInstallDir).Path

switch ($Action) {
	'Info' { $arguments = @('info') }
	'Extract' {
		if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Destination)) { throw 'Extract requires Source and Destination.' }
		$sourcePath = Resolve-RepositoryPath $Source $true
		$destinationPath = Resolve-RepositoryPath $Destination $false
		if (Test-Path -LiteralPath $destinationPath) { throw "Extract destination already exists: $Destination" }
		$arguments = @('extract',$sourcePath,'-extractFolder',$destinationPath,'-modelSerialization','Tmdl','-mashupSerialization','Default')
	}
	'Compile' {
		if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Destination)) { throw 'Compile requires Source and Destination.' }
		$sourcePath = Resolve-RepositoryPath $Source $true
		$destinationPath = Resolve-RepositoryPath $Destination $false
		New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
		$arguments = @('compile',$sourcePath,'-outPath',$destinationPath,'-format','PBIT','-overwrite')
	}
}
& $patchedExe @arguments
if ($LASTEXITCODE -ne 0) { throw "pbi-tools Desktop $Action failed with exit code $LASTEXITCODE." }
