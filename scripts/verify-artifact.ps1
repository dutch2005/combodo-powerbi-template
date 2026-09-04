[CmdletBinding()]
param(
	[ValidateSet('Docker','Desktop')][string]$Extractor = 'Docker',
	[string]$PbiInstallDir,
	[string]$PbiToolsExe,
	[string]$MonoCecilDll
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'src/CombodoPowerBI'
$artifactName = 'Combodo_PowerBI_Reporting_Template_1.1.0.pbit'
$artifact = Join-Path $root "artifacts/$artifactName"
$checksumFile = Join-Path $root 'artifacts/SHA256SUMS.txt'
$temporaryRoot = Join-Path $root '.cache/artifact-verify'
$temporary = Join-Path $temporaryRoot ([guid]::NewGuid().ToString('N'))
. (Join-Path $root 'tests/TestHelpers.ps1')

function Assert-NoReparsePoint([string]$Path)
{
	$current = [System.IO.DirectoryInfo]::new([System.IO.Path]::GetFullPath($Path))
	while ($null -ne $current) {
		if ($current.Exists -and ($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { throw "Unsafe reparse point in temporary path: $($current.FullName)" }
		$current = $current.Parent
	}
}

function Remove-InvocationTemporaryDirectory
{
	if (-not (Test-Path -LiteralPath $temporary)) { return }
	Assert-NoReparsePoint $temporary
	$resolved = (Resolve-Path -LiteralPath $temporary).Path
	if (-not $resolved.Equals($temporary, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe temporary path: $resolved" }
	Remove-Item -LiteralPath $temporary -Recurse -Force
}

& (Join-Path $root 'tests/assert-contract.ps1')
& (Join-Path $root 'tests/assert-model-parity.ps1')
if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "Missing release artifact: $artifactName" }
$expectedHash = ((Get-Content -LiteralPath $checksumFile | Where-Object { $_ -match [regex]::Escape($artifactName) }) -split '\s+')[0]
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash
if ($actualHash -cne $expectedHash) { throw "Artifact checksum mismatch: expected $expectedHash, got $actualHash." }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($artifact)
try {
	$entries = @($archive.Entries | ForEach-Object FullName)
	foreach ($required in @('DataMashup','DataModelSchema','Report/Layout','Version')) {
		if ($entries -cnotcontains $required) { throw "PBIT is missing required entry: $required" }
	}
	$dataMashup = $archive.Entries | Where-Object FullName -ceq 'DataMashup'
	if ($dataMashup.Length -le 0) { throw 'PBIT contains an empty DataMashup.' }
} finally { $archive.Dispose() }

Assert-NoReparsePoint $temporaryRoot
[System.IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
try {
	if ($Extractor -eq 'Docker') {
		$relativeTemporary = $temporary.Substring($root.Length + 1).Replace('\','/')
		& (Join-Path $root 'scripts/pbi-tools.ps1') -Action Extract -Source "artifacts/$artifactName" -Destination $relativeTemporary
	} else {
		foreach ($value in @($PbiInstallDir,$PbiToolsExe,$MonoCecilDll)) {
			if ([string]::IsNullOrWhiteSpace($value)) { throw 'Desktop extraction requires PbiInstallDir, PbiToolsExe, and MonoCecilDll.' }
		}
		$relativeTemporary = $temporary.Substring($root.Length + 1).Replace('\','/')
		& (Join-Path $root 'scripts/pbi-tools-desktop.ps1') -Action Extract -Source "artifacts/$artifactName" -Destination $relativeTemporary -PbiInstallDir $PbiInstallDir -PbiToolsExe $PbiToolsExe -MonoCecilDll $MonoCecilDll
	}
	$groups = @(
		@('Report','StaticResources','DiagramLayout.json','ReportMetadata.json','ReportSettings.json'),
		@('Model'),
		@('Mashup/Package/Config','Mashup/Package/Content','Mashup/Package/Resources','Mashup/Package.xml','Mashup/permissions.json','Mashup/metadata.xml')
	)
	foreach ($group in $groups) {
		$sourceHash = (Get-TreeFingerprint $project $group).sha256
		$artifactHash = (Get-TreeFingerprint $temporary $group).sha256
		if ($sourceHash -cne $artifactHash) { throw "Artifact differs from source in: $($group -join ', ')" }
	}
	$sourceM = Join-Path $project 'Mashup/Package/Formulas/Section1.m'
	$artifactM = Join-Path $temporary 'Mashup/Package/Formulas/Section1.m'
	if ((Get-PortableFileHash $sourceM) -cne (Get-PortableFileHash $artifactM)) { throw 'Artifact Power Query expressions differ from source.' }
	$pageCount = @(Get-ChildItem -LiteralPath (Join-Path $temporary 'Report/sections') -Directory).Count
	$visualCount = @(Get-ChildItem -LiteralPath (Join-Path $temporary 'Report/sections') -Filter 'visualContainer.json' -File -Recurse).Count
	if ($pageCount -ne 10 -or $visualCount -ne 76) { throw "Unexpected report layout: $pageCount pages and $visualCount visuals." }
} finally { Remove-InvocationTemporaryDirectory }
Write-Output "Artifact verified: $actualHash ($pageCount pages, $visualCount visuals, DataMashup present)."
