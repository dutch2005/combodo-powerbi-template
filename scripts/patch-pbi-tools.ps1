[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$InputExe,
	[Parameter(Mandatory)][string]$PackagingDll,
	[Parameter(Mandatory)][string]$MonoCecilDll,
	[Parameter(Mandatory)][string]$ExpectedMonoCecilSha256,
	[Parameter(Mandatory)][string]$OutputExe
)

$ErrorActionPreference = 'Stop'
$monoCecilPath = (Resolve-Path -LiteralPath $MonoCecilDll).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $monoCecilPath).Hash -cne $ExpectedMonoCecilSha256) {
	throw 'Unexpected Mono.Cecil library; use the locked 0.11.5 netstandard2.0 binary.'
}
Add-Type -Path $monoCecilPath
$dependencyDirectory = Join-Path ([System.IO.Path]::GetDirectoryName($OutputExe)) 'resolver'
[System.IO.Directory]::CreateDirectory($dependencyDirectory) | Out-Null
$bootstrap = [Mono.Cecil.ModuleDefinition]::ReadModule((Resolve-Path -LiteralPath $InputExe))
try {
	foreach ($resource in $bootstrap.Resources) {
		if ($resource.Name -notmatch '^costura\.(.+\.dll)\.compressed$') { continue }
		$dependencyPath = Join-Path $dependencyDirectory $Matches[1]
		$inputStream = $resource.GetResourceStream()
		$outputStream = [System.IO.File]::Create($dependencyPath)
		try {
			$deflate = [System.IO.Compression.DeflateStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
			try { $deflate.CopyTo($outputStream) } finally { $deflate.Dispose() }
		} finally {
			$outputStream.Dispose()
			$inputStream.Dispose()
		}
	}
} finally { $bootstrap.Dispose() }

$resolver = [Mono.Cecil.DefaultAssemblyResolver]::new()
$resolver.AddSearchDirectory($dependencyDirectory)
$resolver.AddSearchDirectory([System.IO.Path]::GetDirectoryName($PackagingDll))
$reader = [Mono.Cecil.ReaderParameters]::new()
$reader.AssemblyResolver = $resolver
$module = [Mono.Cecil.ModuleDefinition]::ReadModule((Resolve-Path -LiteralPath $InputExe), $reader)
$packaging = [Mono.Cecil.ModuleDefinition]::ReadModule((Resolve-Path -LiteralPath $PackagingDll), $reader)
try {
	$packageType = $module.Types | Where-Object FullName -eq 'PbiTools.PowerBI.PbiPackage'
	$saveMethod = $packageType.Methods | Where-Object { $_.Name -eq 'Save' -and $_.Parameters.Count -eq 1 }
	$oldCall = $saveMethod.Body.Instructions | Where-Object {
		$_.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Call -and
		$_.Operand.FullName -like '*PowerBIPackager::Save*' -and $_.Operand.Parameters.Count -eq 3
	}
	if ($null -eq $oldCall) { throw 'Expected three-parameter PowerBIPackager.Save call was not found.' }
	$packager = $packaging.Types | Where-Object FullName -eq 'Microsoft.PowerBI.Packaging.PowerBIPackager'
	$newSave = $packager.Methods | Where-Object {
		$_.Name -eq 'Save' -and $_.IsStatic -and $_.Parameters.Count -eq 4 -and
		$_.Parameters[2].ParameterType.FullName -eq 'Microsoft.PowerBI.Packaging.Host.ISecurityBindingsEncrypter'
	}
	if ($null -eq $newSave) { throw 'Expected four-parameter PowerBIPackager.Save overload was not found.' }

	$newCall = [Mono.Cecil.MethodReference]::new('Save', $oldCall.Operand.ReturnType, $oldCall.Operand.DeclaringType)
	$newCall.HasThis = $false
	$newCall.Parameters.Add([Mono.Cecil.ParameterDefinition]::new($oldCall.Operand.Parameters[0].ParameterType))
	$newCall.Parameters.Add([Mono.Cecil.ParameterDefinition]::new($oldCall.Operand.Parameters[1].ParameterType))
	$encrypter = [Mono.Cecil.TypeReference]::new('Microsoft.PowerBI.Packaging.Host', 'ISecurityBindingsEncrypter', $module, $oldCall.Operand.DeclaringType.Scope, $false)
	$newCall.Parameters.Add([Mono.Cecil.ParameterDefinition]::new($encrypter))
	$newCall.Parameters.Add([Mono.Cecil.ParameterDefinition]::new($oldCall.Operand.Parameters[2].ParameterType))
	$il = $saveMethod.Body.GetILProcessor()
	$il.InsertBefore($oldCall.Previous, $il.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
	$oldCall.Operand = $newCall
	[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($OutputExe)) | Out-Null
	$module.Write($OutputExe)
} finally {
	$packaging.Dispose()
	$module.Dispose()
	$resolver.Dispose()
}
Write-Output "Patched pbi-tools written to $OutputExe"
