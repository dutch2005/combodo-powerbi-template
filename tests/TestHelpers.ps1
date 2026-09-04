function Get-PortableFileHash([string]$Path)
{
	$textExtensions = @('.json','.m','.tmdl','.txt','.xml')
	if ($textExtensions -contains [System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
		$text = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd([char]10) + "`n"
		$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
	} else {
		$bytes = [System.IO.File]::ReadAllBytes($Path)
	}
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
	finally { $sha.Dispose() }
}

function Get-TreeFingerprint([string]$TreeRoot, [string[]]$Paths)
{
	$files = foreach ($path in $Paths) {
		$fullPath = Join-Path $TreeRoot $path
		if (Test-Path -LiteralPath $fullPath -PathType Container) { Get-ChildItem -LiteralPath $fullPath -File -Recurse }
		elseif (Test-Path -LiteralPath $fullPath -PathType Leaf) { Get-Item -LiteralPath $fullPath }
	}
	$lines = @($files | Sort-Object FullName | ForEach-Object {
		$relative = $_.FullName.Substring($TreeRoot.Length + 1).Replace('\','/')
		"$relative=$(Get-PortableFileHash $_.FullName)"
	})
	$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n"))
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try {
		return [pscustomobject]@{
			count = $lines.Count
			sha256 = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
		}
	} finally { $sha.Dispose() }
}

function Get-ModelStructureFingerprint([string]$ModelRoot)
{
	$mutableTables = @('UserRequest.tmdl','UserRequest_Period.tmdl','TeamList.tmdl','FirstTeam_Affected.tmdl')
	$lines = @(Get-ChildItem -LiteralPath $ModelRoot -File -Recurse | Where-Object Name -ne 'expressions.tmdl' | Sort-Object FullName | ForEach-Object {
		$relative = $_.FullName.Substring($ModelRoot.Length + 1).Replace('\','/')
		if ($mutableTables -contains $_.Name) {
			$content = [System.IO.File]::ReadAllText($_.FullName).Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd([char]10) + "`n"
			$content = [regex]::Replace($content, '(?ms)(^\tpartition .+? = m\n\t\tmode: import\n)\t\tsource =.*?(?=^\tannotation |\z)', "`$1`t`tsource = <locale-neutral-query>`n`n")
			$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($content)
			$sha = [System.Security.Cryptography.SHA256]::Create()
			try { $fileHash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
			finally { $sha.Dispose() }
		} else { $fileHash = Get-PortableFileHash $_.FullName }
		"$relative=$fileHash"
	})
	$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n"))
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try {
		return [pscustomobject]@{
			count = $lines.Count
			sha256 = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
		}
	} finally { $sha.Dispose() }
}
