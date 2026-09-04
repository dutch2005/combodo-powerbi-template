[CmdletBinding()]
param(
	[Parameter(Mandatory)]
	[ValidateSet('Info', 'Extract', 'Compile')]
	[string]$Action,
	[string]$Source,
	[string]$Destination
)

$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskLockPath = Join-Path $taskRoot 'tools/pbi-tools.lock.json'
$taskLock = Get-Content -Raw -LiteralPath $taskLockPath | ConvertFrom-Json
$taskRootPrefix = $taskRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

function Resolve-TaskPath
{
	param(
		[Parameter(Mandatory)][string]$RelativePath,
		[switch]$MustExist
	)

	if ([System.IO.Path]::IsPathRooted($RelativePath)) {
		throw "Path is outside the repository: $RelativePath"
	}
	$taskFullPath = [System.IO.Path]::GetFullPath((Join-Path $taskRoot $RelativePath))
	if (-not $taskFullPath.StartsWith($taskRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Path is outside the repository: $RelativePath"
	}
	if ($MustExist -and -not (Test-Path -LiteralPath $taskFullPath)) {
		throw "Required path does not exist: $RelativePath"
	}
	return $taskFullPath
}

function ConvertTo-ContainerPath
{
	param([Parameter(Mandatory)][string]$HostPath)
	$taskRelativePath = $HostPath.Substring($taskRoot.Length).TrimStart('\', '/')
	return '/repo/' + $taskRelativePath.Replace('\', '/')
}

$taskDockerArguments = @(
	'run',
	'--rm',
	'--mount',
	"type=bind,source=$taskRoot,target=/repo",
	'--entrypoint',
	'/app/pbi-tools/pbi-tools.core',
	[string]$taskLock.image
)

switch ($Action) {
	'Info' {
		$taskToolArguments = @('info')
	}
	'Extract' {
		if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Destination)) {
			throw 'Extract requires Source and Destination.'
		}
		$taskSourcePath = Resolve-TaskPath -RelativePath $Source -MustExist
		$taskDestinationPath = Resolve-TaskPath -RelativePath $Destination
		if (Test-Path -LiteralPath $taskDestinationPath) {
			throw "Extract destination already exists: $Destination"
		}
		$taskToolArguments = @(
			'extract',
			(ConvertTo-ContainerPath $taskSourcePath),
			'-extractFolder',
			(ConvertTo-ContainerPath $taskDestinationPath),
			'-modelSerialization',
			'Tmdl',
			'-mashupSerialization',
			'Default'
		)
	}
	'Compile' {
		if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Destination)) {
			throw 'Compile requires Source and Destination.'
		}
		$taskSourcePath = Resolve-TaskPath -RelativePath $Source -MustExist
		$taskDestinationPath = Resolve-TaskPath -RelativePath $Destination
		$taskDestinationParent = Split-Path -Parent $taskDestinationPath
		New-Item -ItemType Directory -Path $taskDestinationParent -Force | Out-Null
		$taskToolArguments = @(
			'compile',
			(ConvertTo-ContainerPath $taskSourcePath),
			'-outPath',
			(ConvertTo-ContainerPath $taskDestinationPath),
			'-format',
			'PBIT',
			'-overwrite'
		)
	}
}

$taskDockerArguments += $taskToolArguments
& docker @taskDockerArguments
if ($LASTEXITCODE -ne 0) {
	throw "pbi-tools $Action failed with exit code $LASTEXITCODE."
}
