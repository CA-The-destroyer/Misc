<#

- RDS/FSLogix safe, minimal dependencies
- Chrome path: ProgramFiles(x86) first, then ProgramFiles
- Session-only running check (big red banner)
- Copies ONLY Bookmarks (+ .bak) from current user's active profile -> TargetProfile
- Forgiving if no source profile exists; still launches
#>

param(
    [string]$TargetProfile    = "Youtube_Test",
    [string]$SourceProfile    = "",  # If empty, auto-detect from Local State->last_used, fallback "Default"
    [string]$GoogleSignInUrl  = "https://accounts.google.com/ServiceLogin?hl=en&continue=https://www.google.com/"
)

# --- Locate Chrome (no registry, no per-user path) ---
$chromeCandidates = @(
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromeCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $chrome) { Write-Error "Chrome not found in Program Files(x86) or Program Files."; exit 1 }

# --- Helpers ---
function Get-UserDataDir { Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data" }

function Get-SourceProfileName {
    param([string]$UserDataDir, [string]$Explicit)
    if ($Explicit -and -not [string]::IsNullOrWhiteSpace($Explicit)) { return $Explicit }
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

function Get-MySessionChrome {
    try {
        $mySession = (Get-Process -Id $PID).SessionId
        return @(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession })
    } catch { @() }
}

# --- Paths (per-user; FSLogix-friendly) ---
$userDataDir = Get-UserDataDir
if (-not (Test-Path $userDataDir)) { New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null }

# --- Ensure Chrome is NOT running in THIS SESSION ---
$sessionChrome = Get-MySessionChrome
if ($sessionChrome.Count -gt 0) {
    Write-Host ""
    Write-Host "##############################################" -ForegroundColor Red
    Write-Host "##   CHROME IS RUNNING IN YOUR SESSION!     ##" -ForegroundColor Red
    Write-Host "##   Close ALL Chrome windows, then re-run  ##" -ForegroundColor Red
    Write-Host "##############################################" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# --- Determine source profile (forgiving) ---
$srcProfileName = Get-SourceProfileName -UserDataDir $userDataDir -Explicit $SourceProfile
$skipCopy = $false
if ($srcProfileName) {
    $srcProfileDir = Join-Path $userDataDir $srcProfileName
    if (-not (Test-Path $srcProfileDir)) {
        Write-Host "Source profile '$srcProfileName' missing. Skipping bookmark copy."
        $skipCopy = $true
    }
} else {
    Write-Host "No existing Chrome profile found for this user. Skipping bookmark copy."
    $skipCopy = $true
}

# --- Prepare target profile ---
$dstProfileDir = Join-Path $userDataDir $TargetProfile
if (-not (Test-Path $dstProfileDir)) {
    New-Item -ItemType Directory -Path $dstProfileDir -Force | Out-Null
    Write-Host "Created target profile: $dstProfileDir"
} else {
    Write-Host "Using existing target profile: $dstProfileDir"
}

# --- Copy ONLY bookmarks (and .bak) if valid, different source ---
if (-not $skipCopy) {
    $sameProfile = (Resolve-Path $srcProfileDir).ProviderPath -eq (Resolve-Path $dstProfileDir).ProviderPath
    if ($sameProfile) {
        Write-Host "Source '$srcProfileName' equals target '$TargetProfile'. Skipping bookmark copy."
    } else {
        $srcBookmarks    = Join-Path $srcProfileDir "Bookmarks"
        $srcBookmarksBak = Join-Path $srcProfileDir "Bookmarks.bak"
        $dstBookmarks    = Join-Path $dstProfileDir "Bookmarks"
        $dstBookmarksBak = Join-Path $dstProfileDir "Bookmarks.bak"

        $copied = $false
        if (Test-Path $srcBookmarks)    { Copy-Item $srcBookmarks    $dstBookmarks    -Force; $copied = $true }
        if (Test-Path $srcBookmarksBak) { Copy-Item $srcBookmarksBak $dstBookmarksBak -Force; $copied = $true }

        if ($copied) { Write-Host "Bookmarks copied from '$srcProfileName' -> '$TargetProfile'." }
        else { Write-Host "No bookmarks found to copy from '$srcProfileName'." }
    }
}

# --- Launch Chrome into target profile to Google sign-in ---
Write-Host "Launching Chrome with profile '$TargetProfile' -> $GoogleSignInUrl"
Start-Process -FilePath $chrome -ArgumentList @(
    "--profile-directory=$TargetProfile",
    "--no-first-run",
    "--new-window",
    $GoogleSignInUrl
)
