<#
.SYNOPSIS
  Publish one addon of this repository on brodgar.io/addons: bump the version, zip, upload.

.DESCRIPTION
    .\publish.ps1 gob-cache-map          the manifest's X.Y.Z becomes X.Y.(Z+1), then upload
    .\publish.ps1 gob-cache-map 2.0.0    that version instead (also -Version 2.0.0)

  The version is written into manifest.json before packing, because the hub reads the version from the
  manifest inside the zip, and put back the way it was if the upload fails. The package is the shape the
  client installs: every entry under <id>/ -- <id>/manifest.json, <id>/main.lua, ... -- written with
  System.IO.Compression, not Compress-Archive, which puts backslashes in the entry names.

  The addon is created on the hub the first time (a 409 says it is there already), then the version is
  uploaded. The token is BRODGAR_TOKEN, in the .env file beside this script (git ignores it) or in the
  environment, or -Token; create one at https://brodgar.io/addons/settings. BRODGAR_HUB, set the same
  way, points the script at another hub. Needs curl.exe, which Windows ships.

.PARAMETER Addon
  The addon's folder: a name in this repository, or a path.
.PARAMETER Version
  1.2.3 or 1.2.3-beta.1. Without it, the manifest's X.Y.Z with Z + 1.
.PARAMETER Token
  The hub token, instead of BRODGAR_TOKEN.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Addon,
    [Parameter(Position = 1)][string]$Version,
    [string]$Token
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$skippedFiles = @('luac.out', '.DS_Store', 'Thumbs.db', 'desktop.ini')
$skippedFolders = '(^|/)(\.git|node_modules)/'

# --- .env, the token and the hub ---------------------------------------------------------------------------
# KEY=value per line; a variable the environment already sets wins over the file.
$envFile = Join-Path $PSScriptRoot '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile -Encoding UTF8) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $name = $Matches[1]
            $value = $Matches[2] -replace '^"(.*)"$', '$1' -replace "^'(.*)'$", '$1'
            if (-not (Test-Path "Env:$name")) { Set-Item "Env:$name" $value }
        }
    }
}
if (-not $Token) { $Token = $env:BRODGAR_TOKEN }
if (-not $Token) { throw "no token: put BRODGAR_TOKEN=bio_... in $envFile, or pass -Token (create one at https://brodgar.io/addons/settings)" }
$hub = if ($env:BRODGAR_HUB) { $env:BRODGAR_HUB.TrimEnd('/') } else { 'https://brodgar.io/addons/api' }
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is not on the PATH' }

# --- the addon and its manifest ----------------------------------------------------------------------------
$addonDirectory = if (Test-Path $Addon -PathType Container) { $Addon } else { Join-Path $PSScriptRoot $Addon }
if (-not (Test-Path $addonDirectory -PathType Container)) { throw "no addon folder $Addon (looked at $([System.IO.Path]::Combine((Get-Location).Path, $Addon)) and $addonDirectory)" }
$addonDirectory = (Resolve-Path $addonDirectory).Path.TrimEnd('\', '/')
$id = Split-Path $addonDirectory -Leaf
$manifestPath = Join-Path $addonDirectory 'manifest.json'
if (-not (Test-Path $manifestPath)) { throw "$manifestPath does not exist" }
$originalText = Get-Content $manifestPath -Raw -Encoding UTF8
$manifest = $originalText | ConvertFrom-Json
if ($manifest.id -ne $id) { throw "$manifestPath says id `"$($manifest.id)`" but the folder is $id" }
if (-not $manifest.files) { throw "$manifestPath has no `"files`"" }
foreach ($file in $manifest.files) {
    if (-not (Test-Path (Join-Path $addonDirectory $file) -PathType Leaf)) { throw "$manifestPath lists $file, which is not in the folder" }
}

# --- the version: given, or the manifest's with Z + 1 ------------------------------------------------------
if ($Version) {
    if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { throw "version $Version is not X.Y.Z" }
} else {
    $current = $manifest.version
    if (-not $current) { throw 'manifest.json has no version to bump; pass one' }
    if ($current -notmatch '^(\d+)\.(\d+)\.(\d+)$') { throw "manifest.json's version $current is not X.Y.Z, so it cannot be bumped; pass one" }
    $Version = '{0}.{1}.{2}' -f $Matches[1], $Matches[2], ([int]$Matches[3] + 1)
}
# swapped inside the text itself, so the file keeps its own layout
$versionField = '("version"\s*:\s*")[^"]*(")'
if ($originalText -notmatch $versionField) { throw 'manifest.json has no "version" field; add one' }
$updatedText = [regex]::Replace($originalText, $versionField, '${1}' + $Version + '${2}')
if (($updatedText | ConvertFrom-Json).version -ne $Version) { throw 'could not write the version into manifest.json' }

# --- the hub ------------------------------------------------------------------------------------------------
$responseFile = Join-Path $env:TEMP "brodgar-publish-$id-response.txt"
$listingFile = Join-Path $env:TEMP "brodgar-publish-$id-listing.json"
$zipFile = Join-Path $env:TEMP "brodgar-publish-$id-$Version.zip"

# POST a file to a route; hands back the status and the body, and the body as JSON when it is.
function Invoke-Hub {
    param([string]$Route, [string]$ContentType, [string]$BodyFile)
    if (Test-Path $responseFile) { Remove-Item $responseFile }
    $arguments = @('-sS', '-o', $responseFile, '-w', '%{http_code}', '-X', 'POST', "$hub$Route",
        '-H', "Authorization: Bearer $Token", '-H', "Content-Type: $ContentType", '-H', 'Accept: application/json',
        '--data-binary', "@$BodyFile")
    $status = & curl.exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "could not reach $hub$Route (curl exit code $LASTEXITCODE)" }
    $body = if (Test-Path $responseFile) { (Get-Content $responseFile -Raw -Encoding UTF8) } else { '' }
    $json = $null
    try { $json = $body | ConvertFrom-Json } catch {}
    return @{ Status = [int]$status; Body = $body; Json = $json }
}

function Describe-Error {
    param($Response)
    $message = $Response.Body.Trim()
    if (-not $message) { $message = '(empty response)' }
    if ($Response.Json) {
        foreach ($field in 'error', 'message', 'detail') {
            $named = $Response.Json.$field
            if ($named) { $message = if ($named -is [string]) { $named } else { $named | ConvertTo-Json -Compress }; break }
        }
    }
    return "HTTP $($Response.Status): $message"
}

try {
    # the addon is created once; a 409 says it is there already
    $listing = [ordered]@{
        id = $id
        name = if ($manifest.name) { $manifest.name } else { $id }
        summary = if ($manifest.description) { $manifest.description } else { '' }
    }
    [System.IO.File]::WriteAllText($listingFile, ($listing | ConvertTo-Json -Compress), $utf8NoBom)
    $created = Invoke-Hub -Route '/addons' -ContentType 'application/json' -BodyFile $listingFile
    if ($created.Status -eq 409) {
        Write-Host "$id is on the hub already"
    } elseif ($created.Status -ge 200 -and $created.Status -lt 300) {
        Write-Host "created $id on the hub"
    } else {
        throw "could not create $id on the hub -- $(Describe-Error $created)"
    }

    # from here the manifest on disk carries the new version; it goes back if anything fails
    [System.IO.File]::WriteAllText($manifestPath, $updatedText, $utf8NoBom)
    $published = $false
    try {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        if (Test-Path $zipFile) { Remove-Item $zipFile }
        $archive = [System.IO.Compression.ZipFile]::Open($zipFile, 'Create')
        $count = 0
        try {
            foreach ($file in Get-ChildItem $addonDirectory -Recurse -File | Sort-Object FullName) {
                $relative = $file.FullName.Substring($addonDirectory.Length + 1) -replace '\\', '/'
                if ($skippedFiles -contains $file.Name -or $relative -match $skippedFolders) { continue }
                [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, "$id/$relative", [System.IO.Compression.CompressionLevel]::Optimal)
                $count++
            }
        } finally {
            $archive.Dispose()
        }
        $size = (Get-Item $zipFile).Length
        $sha256 = (Get-FileHash $zipFile -Algorithm SHA256).Hash.ToLower()
        Write-Host ("{0} {1} -> {2}: {3} files, {4:N1} KB zipped" -f $id, $manifest.version, $Version, $count, ($size / 1KB))

        $uploaded = Invoke-Hub -Route "/addons/$id/versions" -ContentType 'application/zip' -BodyFile $zipFile
        if ($uploaded.Status -lt 200 -or $uploaded.Status -ge 300) {
            $hint = if ($uploaded.Status -eq 409) { ' (that version is published already; pass another)' } else { '' }
            throw "could not publish $id $Version -- $(Describe-Error $uploaded)$hint"
        }
        $published = $true
        $result = $uploaded.Json
        Write-Host "published $id $(if ($result.version) { $result.version } else { $Version })"
        if ($result.package_url) { Write-Host "  $($result.package_url)" }
        if ($result.sha256 -and $result.sha256.ToLower() -ne $sha256) { Write-Host "  warning: the hub stored sha256 $($result.sha256), the upload was $sha256" }
    } finally {
        if (-not $published) { [System.IO.File]::WriteAllText($manifestPath, $originalText, $utf8NoBom) }
    }
} finally {
    foreach ($temporary in $responseFile, $listingFile, $zipFile) {
        if (Test-Path $temporary) { Remove-Item $temporary -ErrorAction SilentlyContinue }
    }
}
