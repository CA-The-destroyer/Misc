# Change npm global install location on Windows 11
# Target folder for global packages (bins will live here too)
$Prefix = 'C:\temp\NPM'
$Cache  = Join-Path $Prefix 'cache'

# 1) Create the folders if they don't exist
New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
New-Item -ItemType Directory -Path $Cache  -Force | Out-Null

# 2) Point npm to the new locations (works with npm v8+)
# Prefer the modern flag:
$null = npm config set prefix "$Prefix" --location=global
$null = npm config set cache  "$Cache"  --location=global

# Fallbacks for older npm (safe to run; ignore errors)
try { $null = npm config set prefix "$Prefix" -g } catch {}
try { $null = npm config set cache  "$Cache"  -g } catch {}

# 3) Update the *User* PATH so global executables resolve
# On Windows, npm puts global executables in $Prefix itself.
# Some packages still assume node_modules\.bin—add both for safety.
$pathsToAdd = @($Prefix, (Join-Path $Prefix 'node_modules\.bin'))

# Read current user PATH (not system PATH)
$currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @()
if ($currentUserPath) { $parts = $currentUserPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) }

# Normalize and add missing entries
$normalized = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($p in $parts) { [void]$normalized.Add($p.Trim()) }
foreach ($p in $pathsToAdd) {
    if (-not $normalized.Contains($p)) { $parts += $p }
}

$newUserPath = ($parts -join ';')

# Write it back to HKCU\Environment and user profile env
[Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')

Write-Host "npm prefix set to:  $Prefix"
Write-Host "npm cache  set to:  $Cache"
Write-Host "User PATH updated. Open a new terminal for it to take effect."

# 4) Show verification
Write-Host "`nVerification:"
try {
    $prefixNow = (npm config get prefix --location=global)
} catch {
    $prefixNow = (npm config get prefix -g)
}
Write-Host "npm reports prefix: $prefixNow"
