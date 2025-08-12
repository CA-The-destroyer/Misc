<# 
Create a new Chrome profile and configure Integrated Auth
for silent SSO to Entra ID without copying credentials.
#>

# ---------------------------
# CONFIG
# ---------------------------
$ProfileName = "Youtube_Test"
$IdpUrl = "https://login.microsoftonline.com/"
$AllowlistDomains = "*.microsoftonline.com, login.microsoftonline.com"

# ---------------------------
# STEP 1: Configure Chrome Integrated Auth
# ---------------------------
$chromePolicyKey = 'HKCU:\Software\Policies\Google\Chrome'
New-Item -Path $chromePolicyKey -Force | Out-Null

New-ItemProperty -Path $chromePolicyKey -Name 'AuthServerAllowlist' -Value $AllowlistDomains -PropertyType String -Force | Out-Null
New-ItemProperty -Path $chromePolicyKey -Name 'AuthNegotiateDelegateAllowlist' -Value $AllowlistDomains -PropertyType String -Force | Out-Null
New-ItemProperty -Path $chromePolicyKey -Name 'AuthSchemes' -Value 'negotiate,ntlm' -PropertyType String -Force | Out-Null

Write-Host "Chrome Integrated Auth policies configured for: $AllowlistDomains"

# ---------------------------
# STEP 2: Locate Chrome EXE
# ---------------------------
$chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromePath)) {
    $chromePath = "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
}
if (-not (Test-Path $chromePath)) {
    Write-Error "Google Chrome executable not found."
    exit 1
}

# ---------------------------
# STEP 3: Ensure profile folder exists
# ---------------------------
$userDataDir = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$profilePath = Join-Path $userDataDir $ProfileName

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
    Write-Host "Created new profile folder: $profilePath"
} else {
    Write-Host "Profile folder already exists: $profilePath"
}

# ---------------------------
# STEP 4: Launch Chrome with new profile to Entra ID login
# ---------------------------
Write-Host "Launching Chrome with profile '$ProfileName' to $IdpUrl"
Start-Process -FilePath $chromePath -ArgumentList @(
    "--profile-directory=$ProfileName",
    "--no-first-run",
    "--new-window",
    $IdpUrl
)
