<# 
Per-user Chrome launcher for a clean profile on Terminal Server / RDS.
- No HKCU or HKLM writes
- Creates (if missing) and launches profile "Youtube_Test"
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

# --- Resolve per-user Chrome User Data path (works with FSLogix/Roaming) ---
$userDataDir = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$profilePath = Join-Path $userDataDir $ProfileName

# Ensure User Data root exists
if (-not (Test-Path $userDataDir)) {
    New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
}

# Create profile folder for THIS user if missing (no registry changes)
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
    Write-Host "Created new profile folder: $profilePath"
} else {
    Write-Host "Using existing profile folder: $profilePath"
}

# --- Launch Chrome with the specified profile to Entra ID login ---
Write-Host "Launching Chrome with profile '$ProfileName' -> $IdpUrl"
Start-Process -FilePath $chrome -ArgumentList @(
    "--profile-directory=$ProfileName",
    "--no-first-run",
    "--new-window",
    $IdpUrl
)
