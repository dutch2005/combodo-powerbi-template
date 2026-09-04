$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifact = Join-Path $root 'artifacts/Combodo_PowerBI_Reporting_Template_1.1.1.pbit'
$findings = [System.Collections.Generic.List[string]]::new()
$patterns = [ordered]@{
	InstanceAlias = '(?i)\b' + [char]100 + 'ata4\b'
	PrivateIPv4 = '\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b'
	EmailAddress = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
	LocalUserPath = '(?i)(?:\b[A-Z]:\\Users\\|\\\\[A-Z0-9._-]+\\)'
}

function Test-Text([string]$Name, [string]$Text)
{
	foreach ($entry in $patterns.GetEnumerator()) {
		if ($Text -match $entry.Value) { $findings.Add("$Name contains $($entry.Key): $($Matches[0])") }
	}
}

Get-ChildItem -LiteralPath (Join-Path $root 'src') -File -Recurse |
	Where-Object Extension -notin @('.png','.jpg','.jpeg','.gif') |
	ForEach-Object { Test-Text $_.FullName ([System.IO.File]::ReadAllText($_.FullName)) }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($artifact)
try {
	if (@($archive.Entries | Where-Object FullName -ceq 'DataModel').Count -ne 0) {
		$findings.Add('PBIT contains a cached DataModel payload instead of template-only schema.')
	}
	foreach ($entry in $archive.Entries | Where-Object { $_.FullName -notmatch '\.(?:png|jpg|jpeg|gif)$' -and $_.FullName -ne 'DataMashup' }) {
		$stream = $entry.Open(); $memory = [System.IO.MemoryStream]::new()
		try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
		$bytes = $memory.ToArray(); $memory.Dispose()
		Test-Text "PBIT/$($entry.FullName) UTF-8" ([System.Text.Encoding]::UTF8.GetString($bytes))
		Test-Text "PBIT/$($entry.FullName) UTF-16" ([System.Text.Encoding]::Unicode.GetString($bytes))
	}
	$mashupEntry = @($archive.Entries | Where-Object FullName -ceq 'DataMashup')
	$mashupStream = $mashupEntry[0].Open(); $mashupMemory = [System.IO.MemoryStream]::new()
	try { $mashupStream.CopyTo($mashupMemory) } finally { $mashupStream.Dispose() }
	$mashupBytes = $mashupMemory.ToArray(); $mashupMemory.Dispose()
	$packageLength = [System.BitConverter]::ToInt32($mashupBytes, 4)
	$packageStream = [System.IO.MemoryStream]::new($mashupBytes, 8, $packageLength, $false)
	$package = [System.IO.Compression.ZipArchive]::new($packageStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
	try {
		foreach ($entry in $package.Entries) {
			$reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8, $true)
			try { Test-Text "PBIT/DataMashup/$($entry.FullName)" $reader.ReadToEnd() } finally { $reader.Dispose() }
		}
	} finally { $package.Dispose(); $packageStream.Dispose() }

	$modelEntry = @($archive.Entries | Where-Object FullName -ceq 'DataModelSchema')[0]
	$reader = [System.IO.StreamReader]::new($modelEntry.Open(), [System.Text.Encoding]::Unicode, $true)
	try { $model = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
	foreach ($name in @('user_login','user_password','url_user_request_itop','url_list_team_name_itop','url_list_first_team_dispatched_itop')) {
		$values = @($model.model.expressions | Where-Object name -ceq $name)
		if ($values.Count -ne 1 -or ((@($values[0].expression) -join "`n").Trim() -notmatch '^null\b')) {
			$findings.Add("PBIT parameter $name is not blank.")
		}
	}
} finally { $archive.Dispose() }

if ($findings.Count -ne 0) {
	$findings | ForEach-Object { Write-Error $_ -ErrorAction Continue }
	throw "Personal-data scan failed with $($findings.Count) finding(s)."
}
Write-Output 'Personal-data scan passed: no cached model, populated parameters, instance alias, private IP, email, or local user path.'
