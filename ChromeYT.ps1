# ================================
# Create and Launch Chrome Profile
# Profile Name: Youtube_Test
# ================================

# Path to Chrome executable
$chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromePath)) {
    $chromePath = "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
}

if (-not (Test-Path $chromePath)) {
    Write-Error "Google Chrome not found. Please verify Chrome is installed."
    exit 1
}

# Base directory for custom profiles
$baseDir = Join-Path $env:LOCALAPPDATA "Google\Chrome\CustomProfiles"
$profileName = "Youtube_Test"
$profilePath = Join-Path $baseDir $profileName

# Create profile directory if missing
if (-not (Test-Path $profilePath)) {
    New-Item -Path $profilePath -ItemType Directory -Force | Out-Null
    Write-Host "Created new profile directory: $profilePath"
} else {
    Write-Host "Profile directory already exists: $profilePath"
}

# Launch Chrome with the new profile
Write-Host "Launching Chrome with profile: $profileName"
Start-Process -FilePath $chromePath -ArgumentList @(
    "--user-data-dir=`"$profilePath`"",
    "--profile-directory=Default",
    "--no-first-run",
    "--new-window"
)
