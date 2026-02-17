param(
    [ValidateSet("revision", "patch", "minor", "major")]
    [string]$Level = "revision",

    [Parameter(Mandatory = $true)]
    [string]$Message
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$versionPath = Join-Path $repoRoot "GrindBuddy\version.lua"

if (-not (Test-Path $versionPath)) {
    throw "version.lua not found at $versionPath"
}

$content = Get-Content -Raw $versionPath

$major = [int]([regex]::Match($content, "major\s*=\s*(\d+)").Groups[1].Value)
$minor = [int]([regex]::Match($content, "minor\s*=\s*(\d+)").Groups[1].Value)
$patch = [int]([regex]::Match($content, "patch\s*=\s*(\d+)").Groups[1].Value)
$revision = [int]([regex]::Match($content, "revision\s*=\s*(\d+)").Groups[1].Value)

switch ($Level) {
    "major" {
        $major += 1
        $minor = 0
        $patch = 0
        $revision = 1
    }
    "minor" {
        $minor += 1
        $patch = 0
        $revision = 1
    }
    "patch" {
        $patch += 1
        $revision = 1
    }
    "revision" {
        $revision += 1
    }
}

$content = [regex]::Replace($content, "(?m)^ {4}major\s*=\s*\d+", "    major = $major")
$content = [regex]::Replace($content, "(?m)^ {4}minor\s*=\s*\d+", "    minor = $minor")
$content = [regex]::Replace($content, "(?m)^ {4}patch\s*=\s*\d+", "    patch = $patch")
$content = [regex]::Replace($content, "(?m)^ {4}revision\s*=\s*\d+", "    revision = $revision")

$today = Get-Date -Format "yyyy-MM-dd"
$safeMessage = $Message.Replace('\', '\\').Replace('"', '\"')
$newEntry = "        {`n            revision = $revision,`n            date = `"$today`",`n            summary = `"$safeMessage`",`n        },`n"
$content = [regex]::Replace($content, "(history\s*=\s*\{\s*\r?\n)", "`${1}$newEntry", 1)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($versionPath, $content, $utf8NoBom)

$newVersion = "$major.$minor.$patch-r$revision"
Write-Output "Updated GrindBuddy version: $newVersion"
