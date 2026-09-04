[CmdletBinding()]
param(
	[ValidateSet('Archive','Desktop')][string]$Extractor = 'Archive',
	[string]$PbiInstallDir,
	[string]$PbiToolsExe,
	[string]$MonoCecilDll
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'src/CombodoPowerBI'
$artifactName = 'Combodo_PowerBI_Reporting_Template_1.1.1.pbit'
$artifact = Join-Path $root "artifacts/$artifactName"
$rootArtifact = Join-Path $root 'Combodo_PowerBI_Reporting_Template_V1.07_2210025.pbit'
$checksumFile = Join-Path $root 'artifacts/SHA256SUMS.txt'
$temporaryRoot = Join-Path $root '.cache/artifact-verify'
$temporary = Join-Path $temporaryRoot ([guid]::NewGuid().ToString('N'))
. (Join-Path $root 'tests/TestHelpers.ps1')

function Get-RequiredArchiveEntry($Archive, [string]$Name)
{
	$matches = @($Archive.Entries | Where-Object FullName -ceq $Name)
	if ($matches.Count -ne 1) { throw "PBIT must contain exactly one non-empty $Name entry." }
	if ($matches[0].Length -le 0) { throw "PBIT must contain exactly one non-empty $Name entry." }
	return $matches[0]
}

function Read-ArchiveText($Entry, [System.Text.Encoding]$Encoding)
{
	$reader = [System.IO.StreamReader]::new($Entry.Open(), $Encoding, $true)
	try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Normalize-PortableText([string]$Text)
{
	return $Text.TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd([char]13, [char]10) + "`n"
}

function Normalize-Expression($Expression)
{
	$lines = if ($Expression -is [System.Array]) { @($Expression) } else { @(([string]$Expression) -split "`r?`n") }
	return (($lines | ForEach-Object { $_.TrimStart() }) -join "`n").Trim()
}

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
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $rootArtifact).Hash -cne $actualHash) { throw 'Root PBIT must be byte-identical to the canonical 1.1.1 artifact.' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($artifact)
try {
	$dataMashup = Get-RequiredArchiveEntry $archive 'DataMashup'
	$dataModelEntry = Get-RequiredArchiveEntry $archive 'DataModelSchema'
	$layoutEntry = Get-RequiredArchiveEntry $archive 'Report/Layout'
	[void](Get-RequiredArchiveEntry $archive 'Version')

	$mashupStream = $dataMashup.Open()
	$mashupMemory = [System.IO.MemoryStream]::new()
	try { $mashupStream.CopyTo($mashupMemory) } finally { $mashupStream.Dispose() }
	$mashupBytes = $mashupMemory.ToArray()
	$mashupMemory.Dispose()
	if ($mashupBytes.Length -lt 8) { throw 'DataMashup header is truncated.' }
	$packageLength = [System.BitConverter]::ToInt32($mashupBytes, 4)
	if ($packageLength -le 0 -or 8 + $packageLength -gt $mashupBytes.Length) { throw 'DataMashup package length is invalid.' }
	$packageStream = [System.IO.MemoryStream]::new($mashupBytes, 8, $packageLength, $false)
	$package = [System.IO.Compression.ZipArchive]::new($packageStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
	try {
		$formulaEntry = Get-RequiredArchiveEntry $package 'Formulas/Section1.m'
		$artifactFormula = Read-ArchiveText $formulaEntry ([System.Text.UTF8Encoding]::new($false))
	} finally {
		$package.Dispose()
		$packageStream.Dispose()
	}
	$sourceFormula = [System.IO.File]::ReadAllText((Join-Path $project 'Mashup/Package/Formulas/Section1.m'))
	if ((Normalize-PortableText $artifactFormula) -cne (Normalize-PortableText $sourceFormula)) { throw 'PBIT DataMashup formula differs from source.' }

	$model = (Read-ArchiveText $dataModelEntry ([System.Text.Encoding]::Unicode)) | ConvertFrom-Json
	$expressionSource = [System.IO.File]::ReadAllText((Join-Path $project 'Model/expressions.tmdl'))
	$expressionNames = @('BuildExportUrl','FetchQueryCsv','RequireColumns','ParseITopDateTime','UserRequestFields','UserRequestOutputFields','ShapeUserRequest','ShapeTeamList','ShapeFirstTeam','EmptyFirstTeam')
	foreach ($name in $expressionNames) {
		$artifactExpressions = @($model.model.expressions | Where-Object name -ceq $name)
		$sourceMatch = [regex]::Match($expressionSource, "(?ms)^expression $([regex]::Escape($name))\s*=\s*(.*?)(?=^\tannotation |^expression |\z)")
		if ($artifactExpressions.Count -ne 1 -or -not $sourceMatch.Success) { throw "PBIT model expression is missing or duplicated: $name" }
		if ((Normalize-Expression $artifactExpressions[0].expression) -cne (Normalize-Expression $sourceMatch.Groups[1].Value)) { throw "PBIT model expression differs from source: $name" }
	}
	$measureTable = @($model.model.tables | Where-Object name -ceq 'TableMesures')
	$yearMeasure = @($measureTable[0].measures | Where-Object name -ceq 'Count UR Create Team An')
	$yearExpression = (@($yearMeasure[0].expression) -join "`n")
	if ($measureTable.Count -ne 1 -or $yearMeasure.Count -ne 1 -or -not $yearExpression.Contains('(YEAR([Start date (date)]))=year') -or $yearExpression.Contains('(YEAR([Start date (date)])*100)=year')) {
		throw 'PBIT contains the defective yearly team measure.'
	}
	foreach ($tableName in @('UserRequest','UserRequest_Period','TeamList','FirstTeam_Affected','Calendrier','Calendrier_ResolutionDate')) {
		$artifactTables = @($model.model.tables | Where-Object name -ceq $tableName)
		$tableSource = [System.IO.File]::ReadAllText((Join-Path $project "Model/tables/$tableName.tmdl"))
		$sourceMatch = [regex]::Match($tableSource, '(?ms)^\tpartition .+? = m\s+mode: import\s+source =\s*(.*?)(?=^\tannotation |\z)')
		if ($artifactTables.Count -ne 1 -or $artifactTables[0].partitions.Count -ne 1 -or -not $sourceMatch.Success) { throw "PBIT model partition is missing or duplicated: $tableName" }
		if ((Normalize-Expression $artifactTables[0].partitions[0].source.expression) -cne (Normalize-Expression $sourceMatch.Groups[1].Value)) { throw "PBIT model partition differs from source: $tableName" }
	}

	$layout = (Read-ArchiveText $layoutEntry ([System.Text.Encoding]::Unicode)) | ConvertFrom-Json
	$pageCount = @($layout.sections).Count
	$visualCount = @($layout.sections | ForEach-Object { $_.visualContainers }).Count
	if ($pageCount -ne 10 -or $visualCount -ne 76) { throw "Unexpected embedded report layout: $pageCount pages and $visualCount visuals." }
	$yearSlicerIds = @('27db418e3b6a5e7ca807','9155de0972872601d5b3')
	foreach ($visualId in $yearSlicerIds) {
		$visuals = @($layout.sections.visualContainers | Where-Object { (($_.config | ConvertFrom-Json).name) -ceq $visualId })
		if ($visuals.Count -ne 1 -or $visuals[0].config.Contains("'2022'")) { throw "PBIT retains stale 2022 state in visual $visualId." }
	}
} finally { $archive.Dispose() }

if ($Extractor -eq 'Archive') {
	Write-Output "Artifact archive verified: $actualHash ($pageCount pages, $visualCount visuals, source-bound Mashup and model)."
	return
}

Assert-NoReparsePoint $temporaryRoot
[System.IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
try {
	foreach ($value in @($PbiInstallDir,$PbiToolsExe,$MonoCecilDll)) {
		if ([string]::IsNullOrWhiteSpace($value)) { throw 'Desktop extraction requires PbiInstallDir, PbiToolsExe, and MonoCecilDll.' }
	}
	$relativeTemporary = $temporary.Substring($root.Length + 1).Replace('\','/')
	& (Join-Path $root 'scripts/pbi-tools-desktop.ps1') -Action Extract -Source "artifacts/$artifactName" -Destination $relativeTemporary -PbiInstallDir $PbiInstallDir -PbiToolsExe $PbiToolsExe -MonoCecilDll $MonoCecilDll
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
