<#
Per-user Chrome launcher for Terminal Server / RDS.
- Creates (if missing) and launches profile "Youtube_Test"
- Copies bookmarks from "Default" profile if present
- Opens Entra ID login page
#>

param(
    [string]$ProfileName = "Youtube_Test",
    [string]$IdpUrl      = "https://login.microsoftonline.com/"
)

# --- Locate Chrome (user scope, no admin required) ---
$chrome = Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) {
    $chrome = Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"
}
if (-not (Test-Path $chrome)) {
    Write-Error "Google Chrome not found in Program Files. Install Chrome, then re-run."
    exit 1
}

# --- Resolve per-user Chrome User Data path ---
$userDataDir = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$profilePath = Join-Path $userDataDir $ProfileName
$defaultProfilePath = Join-Path $userDataDir "Default"
$defaultBookmarks = Join-Path $defaultProfilePath "Bookmarks"
$newBookmarks = Join-Path $profilePath "Bookmarks"

# Ensure User Data root exists
if (-not (Test-Path $userDataDir)) {
    New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
}

# --- Ensure profile folder exists ---
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
    Write-Host "Created new profile folder: $profilePath"
} else {
    Write-Host "Using existing profile folder: $profilePath"
}

# --- Copy bookmarks from Default if they exist and new profile doesn't have them ---
if (Test-Path $defaultBookmarks) {
    try {
        # Make sure Chrome is not running
        if (Get-Process chrome -ErrorAction SilentlyContinue) {
            Write-Warning "Chrome is running. Close all Chrome windows before copying bookmarks."
        } else {
            Copy-Item -Path $defaultBookmarks -Destination $newBookmarks -Force
            Write-Host "Bookmarks copied from Default profile to $ProfileName."
        }
    } catch {
        Write-Warning "Failed to copy bookmarks: $($_.Exception.Message)"
    }
} else {
    Write-Host "No bookmarks found in Default profile."
}

# --- Launch Chrome with the specified profile ---
Write-Host "Launching Chrome with profile '$ProfileName' -> $IdpUrl"
Start-Process -FilePath $chrome -ArgumentList @(
    "--profile-directory=$ProfileName",
    "--no-first-run",
    "--new-window",
    $IdpUrl
)
