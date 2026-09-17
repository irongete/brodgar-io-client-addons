<#
.SYNOPSIS
  Publish one addon of this repository on brodgar.io/addons: the next version, zip, upload, commit.

.DESCRIPTION
    .\publish.ps1 gob-cache-map                 the next number: Z + 1 of the manifest's X.Y.Z, or of the hub's if higher
    .\publish.ps1 -Version 2.0.0 gob-cache-map  that number instead (also `gob-cache-map 2.0.0`)

  An addon's version is X.Y.Z, nothing else: the hub has no channels, so whatever is published is what every
  client installs -- test an addon locally first (the launcher's addons.dir, or the client's `ant bin`).
  Every publish takes a new number, Z + 1 of the highest so far: the manifest's, or the hub's latest when
  that is higher (a bump published from another checkout, say), so the upload is never refused as not
  higher. -Version names it instead, and has to be above both.

  The addon's folder has to be committed: the published bytes are then a commit, and the version is one
  too, since the script writes the number into manifest.json, packs, uploads, and commits that file as
  "<id> <version>". If the upload fails the manifest is put back and nothing is committed.

  The package is the shape the client installs: every entry under <id>/ -- <id>/manifest.json,
  <id>/main.lua, ... -- written with System.IO.Compression, not Compress-Archive, which puts backslashes
  in the entry names. The addon is created on the hub the first time (a 409 says it is there already), then
  the version is uploaded. The token is BRODGAR_TOKEN, in the .env file beside this script (git ignores it)
  or in the environment, or -Token; create one at https://brodgar.io/addons/settings. BRODGAR_HUB, set
  the same way, points the script at another hub. Needs git and curl.exe, which Windows ships.

.PARAMETER Addon
  The addon's folder: a name in this repository, or a path.
.PARAMETER Version
  X.Y.Z. Without it, Z + 1 of the highest of the manifest's and the hub's.
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
# committed, so the published bytes are a commit; untracked files count, since they would be packed
$dirty = git -C $addonDirectory status --porcelain -- .
if ($LASTEXITCODE -ne 0) { throw "$addonDirectory is not in a git repository, and a published version is a commit" }
if ($dirty) { throw "$id has uncommitted changes -- commit them first, so the published version is a commit:`n$($dirty -join "`n")" }
$manifestPath = Join-Path $addonDirectory 'manifest.json'
if (-not (Test-Path $manifestPath)) { throw "$manifestPath does not exist" }
$originalText = Get-Content $manifestPath -Raw -Encoding UTF8
$manifest = $originalText | ConvertFrom-Json
if ($manifest.id -ne $id) { throw "$manifestPath says id `"$($manifest.id)`" but the folder is $id" }
if (-not $manifest.files) { throw "$manifestPath has no `"files`"" }
foreach ($file in $manifest.files) {
    if (-not (Test-Path (Join-Path $addonDirectory $file) -PathType Leaf)) { throw "$manifestPath lists $file, which is not in the folder" }
}

# --- the version: named, or Z + 1 of the highest of the manifest's and the hub's --------------------------
# X.Y.Z as a sortable key; $null for anything else.
function Version-Key {
    param([string]$Text)
    if ($Text -notmatch '^(\d+)\.(\d+)\.(\d+)$') { return $null }
    return '{0:D9}.{1:D9}.{2:D9}' -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]
}
$manifestVersion = $manifest.version
if (-not $manifestVersion) { throw 'manifest.json has no version; add one' }
if (-not (Version-Key $manifestVersion)) { throw "manifest.json's version $manifestVersion is not X.Y.Z" }
# the hub's latest: none when the addon is not there yet (404), an error when the hub cannot be reached
$responseFile = Join-Path $env:TEMP "brodgar-publish-$id-response.txt"
if (Test-Path $responseFile) { Remove-Item $responseFile }
$status = & curl.exe -sS -o $responseFile -w '%{http_code}' -H 'Accept: application/json' "$hub/addons/$id"
if ($LASTEXITCODE -ne 0) { throw "could not reach $hub/addons/$id (curl exit code $LASTEXITCODE)" }
$hubVersion = $null
if ([int]$status -eq 200) {
    $hubVersion = ((Get-Content $responseFile -Raw -Encoding UTF8) | ConvertFrom-Json).version
    if ($hubVersion -and -not (Version-Key $hubVersion)) { throw "the hub serves $id $hubVersion, which is not X.Y.Z: name the version" }
} elseif ([int]$status -ne 404) {
    throw "the hub answered HTTP $status for $id"
}
$highest = $manifestVersion
if ($hubVersion -and ((Version-Key $hubVersion) -gt (Version-Key $manifestVersion))) { $highest = $hubVersion }
if ($Version) {
    if (-not (Version-Key $Version)) { throw "the version must be X.Y.Z (an addon has no beta), not '$Version'" }
    if ((Version-Key $Version) -le (Version-Key $highest)) { throw "$id is at $highest already$(if ($highest -eq $hubVersion) { ' on the hub' }): name a version above it, or leave -Version out" }
} else {
    $highest -match '^(\d+)\.(\d+)\.(\d+)$' | Out-Null
    $Version = '{0}.{1}.{2}' -f $Matches[1], $Matches[2], ([int]$Matches[3] + 1)
}
Write-Host "$id $manifestVersion$(if ($hubVersion -and $hubVersion -ne $manifestVersion) { " (the hub serves $hubVersion)" }) -> $Version"
# swapped inside the text itself, so the file keeps its own layout
$versionField = '("version"\s*:\s*")[^"]*(")'
if ($originalText -notmatch $versionField) { throw 'manifest.json has no "version" field; add one' }
$updatedText = [regex]::Replace($originalText, $versionField, '${1}' + $Version + '${2}')
if (($updatedText | ConvertFrom-Json).version -ne $Version) { throw 'could not write the version into manifest.json' }

# --- the hub ------------------------------------------------------------------------------------------------
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
        Write-Host ("{0} {1}: {2} files, {3:N1} KB zipped" -f $id, $Version, $count, ($size / 1KB))

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
    # the version is a commit: the manifest alone, whatever else the index holds
    & git -C $addonDirectory commit -q -m "$id $Version" -- $manifestPath
    if ($LASTEXITCODE -ne 0) { throw "$id $Version is published, but the manifest could not be committed: commit $manifestPath by hand" }
    Write-Host "committed $id $Version ($((git -C $addonDirectory rev-parse --short HEAD).Trim()))"
} finally {
    foreach ($temporary in $responseFile, $listingFile, $zipFile) {
        if (Test-Path $temporary) { Remove-Item $temporary -ErrorAction SilentlyContinue }
    }
}
