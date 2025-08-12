<#
Safe Chrome profile setup for RDS/FSLogix:
- Per-user, no HKCU/HKLM writes
- Copies ONLY bookmarks from source profile
- Launches to Google sign-in (user enables Sync)
- Owner check relaxed: allows if current user has Modify rights; -SkipOwnerCheck to force
#>

param(
    [string]$ProfileName     = "Youtube_Test",
    [string]$SourceProfile   = "Default",
    [string]$GoogleSignInUrl = "https://accounts.google.com/ServiceLogin?hl=en&continue=https://www.google.com/",
    [switch]$SkipOwnerCheck
)

function Test-UserHasModify {
    param([string]$Path, [string]$UserSid)
    try {
        $acl = Get-Acl -Path $Path
        # Translate all ACEs to SIDs for robust match
        foreach ($ace in $acl.Access) {
            $sid = $null
            try { $sid = ($ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])).Value } catch { continue }
            if ($sid -eq $UserSid) {
                if ($ace.FileSystemRights.ToString() -match 'Modify|FullControl|Write') {
                    if ($ace.AccessControlType -eq 'Allow') { return $true }
                }
            }
        }
    } catch { }
    return $false
}

# --- Locate Chrome ---
$chrome = Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) { $chrome = Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe" }
if (-not (Test-Path $chrome)) { Write-Error "Chrome not found."; exit 1 }

# --- Paths (per-user, FSLogix friendly) ---
$userDataDir   = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$srcProfileDir = Join-Path $userDataDir $SourceProfile
$dstProfileDir = Join-Path $userDataDir $ProfileName

# --- Chrome must be closed ---
if (Get-Process chrome -ErrorAction SilentlyContinue) {
    Write-Error "Chrome is running. Close all Chrome windows and re-run."
    exit 1
}

# --- Validate source profile ---
if (-not (Test-Path $srcProfileDir)) { Write-Error "Source profile not found: $srcProfileDir"; exit 1 }

# --- Guard: owner/rights check (relaxed) ---
if (-not $SkipOwnerCheck) {
    try {
        $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $owner      = (Get-Acl $srcProfileDir).Owner
        $ownerSid   = (New-Object System.Security.Principal.NTAccount($owner)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        Write-Warning "Owner check could not translate: $($_.Exception.Message). Proceeding with rights check only."
        $ownerSid = $null
    }

    $hasModify = Test-UserHasModify -Path $srcProfileDir -UserSid $currentSid

    # Allow if owner is current user OR current user has Modify; warn if owner is SYSTEM/Administrators but rights are OK
    $wellKnownOwners = @('S-1-5-18', 'S-1-5-32-544') # SYSTEM, BUILTIN\Administrators
    if (($ownerSid -ne $currentSid) -and -not $hasModify -and ($ownerSid -notin $wellKnownOwners)) {
        Write-Error "Source profile appears to belong to another user and you lack Modify rights. Aborting."
        exit 1
    } elseif ($ownerSid -in $wellKnownOwners) {
        Write-Host "Note: Source profile owner is $owner (expected on FSLogix). Current user has sufficient rights: $hasModify"
    }
}

# --- Ensure destination profile directory exists ---
if (-not (Test-Path $dstProfileDir)) {
    New-Item -ItemType Directory -Path $dstProfileDir -Force | Out-Null
    Write-Host "Created profile: $dstProfileDir"
} else {
    Write-Host "Using existing profile: $dstProfileDir"
}

# --- Copy ONLY bookmarks ---
$srcBookmarks    = Join-Path $srcProfileDir "Bookmarks"
$srcBookmarksBak = Join-Path $srcProfileDir "Bookmarks.bak"
$dstBookmarks    = Join-Path $dstProfileDir "Bookmarks"
$dstBookmarksBak = Join-Path $dstProfileDir "Bookmarks.bak"

$copied = $false
if (Test-Path $srcBookmarks)    { Copy-Item $srcBookmarks    $dstBookmarks    -Force; $copied = $true }
if (Test-Path $srcBookmarksBak) { Copy-Item $srcBookmarksBak $dstBookmarksBak -Force; $copied = $true }

Write-Host ($(if ($copied) { "Bookmarks copied from '$SourceProfile' to '$ProfileName'." } else { "No bookmarks found to copy from '$SourceProfile'." }))

# --- Launch Chrome to Google sign-in ---
Write-Host "Launching Chrome with profile '$ProfileName' -> $GoogleSignInUrl"
Start-Process -FilePath $chrome -ArgumentList @(
    "--profile-directory=$ProfileName",
    "--no-first-run",
    "--new-window",
    $GoogleSignInUrl
)
