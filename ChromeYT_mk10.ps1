<#
Chrome-BookmarksCopy_mk9_Red.ps1
- Copies ONLY the current user's Chrome bookmarks from their active profile to TargetProfile (default: Youtube_Test)
- Fixed Chrome path: ProgramFiles(x86)\Google\Chrome\Application\chrome.exe
- RDS/FSLogix-safe: per-user only, ignores other users' Chrome
- Detects source from Local State -> profile.last_used; falls back to Default
- SKIPS COPY if source == target (avoids self-overwrite)
- BIG RED WARNING if Chrome is running for the current user
- Launches TargetProfile to Google sign-in
#>

param(
    [string]$TargetProfile   = "Youtube_Test",
    [string]$SourceProfile   = "",
    [string]$GoogleSignInUrl = "https://accounts.google.com/ServiceLogin?hl=en&continue=https://www.google.com/"
)

# --- Fixed Chrome path (x86 only) ---
$chrome = "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) {
    Write-Error "Chrome not found at: $chrome"
    exit 1
}

# --- Helpers ---
function Get-CurrentUserChromeProcs {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    @(Get-WmiObject Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $o = $_.GetOwner()
        $owner = if ($o) { "$($o.Domain)\$($o.User)" } else { "" }
        if ($owner -eq $me) { $_ }
    })
}

function Get-UserDataDir {
    Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
}

function Get-SourceProfileName {
    param([string]$UserDataDir)
    # Honor explicit -SourceProfile if provided
    if ($PSBoundParameters.ContainsKey('SourceProfile') -and -not [string]::IsNullOrWhiteSpace($SourceProfile)) {
        return $SourceProfile
    }
    # Try Local State -> profile.last_used
    $localState = Join-Path $UserDataDir "Local State"
    if (Test-Path $localState) {
        try {
            $json = Get-Content $localState -Raw | ConvertFrom-Json
            $last = $json.profile.last_used
            if ($last -and (Test-Path (Join-Path $UserDataDir $last))) { return $last }
        } catch { }
    }
    # Fallback to Default
    if (Test-Path (Join-Path $UserDataDir "Default")) { return "Default" }
    return $null
}

# --- Paths (per-user; FSLogix-friendly) ---
$userDataDir = Get-UserDataDir
if (-not (Test-Path $userDataDir)) {
    New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
}

# --- Ensure Chrome is NOT running for THIS user (ignore others) ---
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
if (-not $srcProfileName) {
    Write-Error "Could not determine a source profile (no Local State/Default). Launch Chrome once, then re-run."
    exit 1
}
$srcProfileDir = Join-Path $userDataDir $srcProfileName

if (-not (Test-Path $srcProfileDir)) {
    Write-Error "Source profile not found: $srcProfileDir"
    exit 1
}

# --- Prepare target profile ---
$dstProfileDir = Join-Path $userDataDir $TargetProfile
if (-not (Test-Path $dstProfileDir)) {
    New-Item -ItemType Directory -Path $dstProfileDir -Force | Out-Null
    Write-Host "Created target profile: $dstProfileDir"
} else {
    Write-Host "Using existing target profile: $dstProfileDir"
}

# --- If source == target, skip copy to avoid self-overwrite ---
$sourceEqualsTarget = (Resolve-Path $srcProfileDir).ProviderPath -eq (Resolve-Path $dstProfileDir).ProviderPath
if ($sourceEqualsTarget) {
    Write-Host "Source profile '$srcProfileName' is the same as target '$TargetProfile'. Skipping bookmark copy."
} else {
    # --- Copy ONLY bookmarks (and .bak if present) ---
    $srcBookmarks    = Join-Path $srcProfileDir "Bookmarks"
    $srcBookmarksBak = Join-Path $srcProfileDir "Bookmarks.bak"
    $dstBookmarks    = Join-Path $dstProfileDir "Bookmarks"
    $dstBookmarksBak = Join-Path $dstProfileDir "Bookmarks.bak"

    $copyAny = $false
    if (Test-Path $srcBookmarks) {
        if (-not (Test-Path $dstBookmarks) -or ((Resolve-Path $srcBookmarks).ProviderPath -ne (Resolve-Path $dstBookmarks).ProviderPath)) {
            Copy-Item $srcBookmarks $dstBookmarks -Force
            $copyAny = $true
        } else {
            Write-Host "Bookmarks source and destination are identical; skipping."
        }
    }
    if (Test-Path $srcBookmarksBak) {
        if (-not (Test-Path $dstBookmarksBak) -or ((Resolve-Path $srcBookmarksBak).ProviderPath -ne (Resolve-Path $dstBookmarksBak).ProviderPath)) {
            Copy-Item $srcBookmarksBak $dstBookmarksBak -Force
            $copyAny = $true
        } else {
            Write-Host "Bookmarks.bak source and destination are identical; skipping."
        }
    }

    if ($copyAny) { Write-Host "Bookmarks copied from '$srcProfileName' -> '$TargetProfile'." }
    else { Write-Host "No bookmarks copied (none found or identical paths)." }
}

# --- Launch Chrome into target profile to Google sign-in (user enables Sync) ---
Write-Host "Launching Chrome with profile '$TargetProfile' -> $GoogleSignInUrl"
Start-Process -FilePath $chrome -ArgumentList @(
    "--profile-directory=$TargetProfile",
    "--no-first-run",
    "--new-window",
    $GoogleSignInUrl
)
