<#
Chrome-BookmarksCopy_mk11.ps1
- Copies ONLY the current user's Chrome bookmarks from their active profile to TargetProfile (default: Youtube_Test)
- RDS/FSLogix-safe: per-user only, ignores other users' Chrome
- Detects source from Local State -> profile.last_used; falls back to Default
- SKIPS COPY if source == target (avoids overwrite with itself)
- BIG RED WARNING if Chrome is running for the current user
- Launches TargetProfile to Google sign-in
#>

param(
    [string]$TargetProfile   = "Youtube_Test",
    [string]$SourceProfile   = "",
    [string]$GoogleSignInUrl = "https://accounts.google.com/ServiceLogin?hl=en&continue=https://www.google.com/"
)

# --- Helpers ---
function Get-ChromePath {
    $candidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-CurrentUserChromeProcs {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    @(Get-WmiObject Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $o = $_.GetOwner()
        $owner = if ($o) { "$($o.Domain)\$($o.User)" } else { "" }
        if ($owner -eq $me) { $_ }
    })
}

function Get-UserDataDir { Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data" }

function Get-SourceProfileName {
    param([string]$UserDataDir)
    if ($PSBoundParameters.ContainsKey('SourceProfile') -and -not [string]::IsNullOrWhiteSpace($SourceProfile)) {
        return $SourceProfile
    }
    $localState = Join-Path $UserDataDir "Local State"
    if (Test-Path $localState) {
        try {
            $json = Get-Content $localState -Raw | ConvertFrom-Json
            $last = $json.profile.last_used
            if ($last -and (Test-Path (Join-Path $UserDataDir $last))) { return $last }
        } catch { }
    }
    if (Test-Path (Join-Path $UserDataDir "Default")) { return "Default" }
    return $null
}

# --- Locate Chrome ---
$chrome = Get-ChromePath
if (-not $chrome) { Write-Error "Chrome not found in Program Files."; exit 1 }

# --- Paths ---
$userDataDir = Get-UserDataDir
if (-not (Test-Path $userDataDir)) { New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null }

# --- Check Chrome for THIS user only ---
$myChrome = Get-CurrentUserChromeProcs
if ($myChrome.Count -gt 0) {
    Write-Host ""
    Write-Host "##############################################" -ForegroundColor Red
    Write-Host "##   CHROME IS RUNNING FOR YOUR ACCOUNT!    ##" -ForegroundColor Red
    Write-Host "##   Please close ALL Chrome windows first  ##" -ForegroundColor Red
    Write-Host "##############################################" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# --- Determine source profile ---
$srcProfileName = Get-SourceProfileName -UserDataDir $userDataDir
if (-not $srcProfileName) { Write-Error "No source profile found. Open Chrome once, then re-run."; exit 1 }

$srcProfileDir = Join-Path $userDataDir $srcProfileName
$dstProfileDir = Join-Path $userDataDir $TargetProfile

if (-not (Test-Path $srcProfileDir)) { Write-Error "Source profile not found: $srcProfileDir"; exit 1 }
if (-not (Test-Path $dstProfileDir)) {
    New-Item -ItemType Directory -Path $dstProfileDir -Force | Out-Null
    Write-Host "Created target profile: $dstProfileDir"
} else {
    Write-Host "Using existing target profile: $dstProfileDir"
}

# --- If source == target, skip copy ---
if ((Resolve-Path $srcProfileDir).ProviderPath -eq (Resolve-Path $dstProfileDir).ProviderPath) {
    Write-Host "Source profile '$srcProfileName' is the same as target '$TargetProfile'. Skipping bookmark copy."
} else {
    # --- Copy ONLY bookmarks ---
    $srcBookmarks    = Join-Path $srcProfileDir "Bookmarks"
    $srcBookmarksBak = Join-Path $srcProfileDir "Bookmarks.bak"
    $dstBookmarks    = Join-Path $dstProfileDir "Bookmarks"
    $dstBookmarksBak = Join-Path $dstProfileDir "Bookmarks.bak"

    $copyAny = $false
    if (Test-Path $srcBookmarks) {
        if (-not (Test-Path $dstBookmarks) -or ((Resolve-Path $srcBookmarks).ProviderPath -ne (Resolve-Path $dstBookmarks).ProviderPath)) {
            Copy-Item $srcBookmarks $dstBookmarks -Force
            $copyAny = $true
        }
    }
    if (Test-Path $srcBookmarksBak) {
        if (-not (Test-Path $dstBookmarksBak) -or ((Resolve-Path $srcBookmarksBak).ProviderPath -ne (Resolve-Path $dstBookmarksBak).ProviderPath)) {
            Copy-Item $srcBookmarksBak $dstBookmarksBak -Force
            $copyAny = $true
        }
    }

    if ($copyAny) { Write-Host "Bookmarks copied from '$srcProfileName' -> '$TargetProfile'." }
    else { Write-Host "No bookmarks copied (none found or identical paths)." }
}

# --- Launch Chrome into target profile ---
Write-Host "Launching Chrome with profile '$TargetProfile' -> $GoogleSignInUrl"
Start-Process -FilePath $chrome -ArgumentList @(
    "--profile-directory=$TargetProfile",
    "--no-first-run",
    "--new-window",
    $GoogleSignInUrl
)
