<#
Manage npm global prefix on Windows 11 with optional nvm-windows awareness

Behavior:
- Default target prefix: C:\Dev
- Migration ONLY happens *to* C:\Dev and ONLY from %APPDATA%\npm (if it exists)
- No migration ever occurs *from* C:\Dev
- On -Revert: switch prefix back to original (captured on first run), update PATH, no file copy
- Writes "prefix=<target>" to the user-level ~/.npmrc so it survives nvm-windows version switches
  (use -NoUserNpmrc to skip writing ~/.npmrc)

Parameters:
  -Prefix        <string>  Target npm global prefix (default: 'C:\Dev')
  -Revert                  Revert to original npm prefix (no migration from C:\Dev)
  -SkipTest                Skip installing and running the 'cowsay' test CLI
  -DryRun                  Show what would be done without making changes
  -NoUserNpmrc             Do not write/modify the user-level ~/.npmrc
  -KeepSource              Keep %APPDATA%\npm entries in PATH after migration (files are never deleted)

Examples:
  # Set npm prefix to C:\Dev, migrate from %APPDATA%\npm if it exists, persist in ~/.npmrc
  .\NPM_Path_Change.ps1

  # Set npm prefix to D:\NodeGlobal (no migration, only changes prefix and PATH), persist ~/.npmrc
  .\NPM_Path_Change.ps1 -Prefix 'D:\NodeGlobal'

  # Migrate to C:\Dev but keep old %APPDATA%\npm PATH entries too
  .\NPM_Path_Change.ps1 -KeepSource

  # Set npm prefix to C:\Dev but skip test package
  .\NPM_Path_Change.ps1 -SkipTest

  # Dry-run the actions without making changes
  .\NPM_Path_Change.ps1 -DryRun

  # Revert npm prefix back to original (no migration), keep ~/.npmrc in sync
  .\NPM_Path_Change.ps1 -Revert

  # Revert, skip test, and don't touch ~/.npmrc
  .\NPM_Path_Change.ps1 -Revert -SkipTest -NoUserNpmrc
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$Prefix = 'C:\Dev',
    [switch]$Revert,
    [switch]$SkipTest,
    [switch]$DryRun,
    [switch]$NoUserNpmrc,
    [switch]$KeepSource
)

#----------------- constants -----------------
$DefaultUserNpm  = Join-Path $env:APPDATA 'npm'       # the only allowed migration source
$StateDir        = Join-Path $env:LOCALAPPDATA 'NpmPrefixMgr'
$StatePath       = Join-Path $StateDir 'state.json'
$UserNpmrcPath   = Join-Path $env:USERPROFILE '.npmrc'

#----------------- utils -----------------
function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-Step($m){ Write-Host ">>> $m" -ForegroundColor Green }
function Ensure-Directory($p){
    if ($DryRun){ Write-Info "DRYRUN mkdir $p" }
    else { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
function Try-NpmConfigSet($k,$v){
    try { if(-not $DryRun){ npm config set $k $v --location=global | Out-Null }; $true }
    catch {
        try { if(-not $DryRun){ npm config set $k $v -g | Out-Null }; $true }
        catch { Write-Warning "Failed npm config set $k=$v : $_"; $false }
    }
}
function Get-NpmPrefix(){
    try { (npm config get prefix --location=global).Trim() }
    catch { (npm config get prefix -g).Trim() }
}
function Get-NpmRoot(){ (npm root -g).Trim() }

# Robust bin resolver (works even if `npm bin -g` isn't supported)
function Get-NpmBin(){
    $bin = $null
    try {
        $bin = (npm bin -g).Trim()
        if ($bin -and (Test-Path $bin)) { return $bin }
    } catch { }
    $pref = Get-NpmPrefix
    if (-not [string]::IsNullOrWhiteSpace($pref)) {
        $candidate = Join-Path $pref 'node_modules\.bin'
        if (Test-Path $candidate) { return $candidate }
        if (Test-Path $pref) { return $pref } # older npm on Windows drops shims here
    }
    return $null
}

function Read-State(){ if(Test-Path $StatePath){ try{ Get-Content $StatePath -Raw | ConvertFrom-Json }catch{$null} } }
function Write-State([string]$op){
    Ensure-Directory $StateDir
    $obj=[pscustomobject]@{ originalPrefix = $op; savedAt = Get-Date }
    if($DryRun){ Write-Info "DRYRUN write-state originalPrefix=$op" }
    else { $obj | ConvertTo-Json | Set-Content -Path $StatePath -Encoding UTF8 }
}
function PathPiecesFromPrefix($p){ ,$p,(Join-Path $p 'node_modules\.bin') }

function Add-UserPathEntries([string[]]$e){
  $userPath=[Environment]::GetEnvironmentVariable('Path','User')
  $parts=@(); if($userPath){ $parts=$userPath.Split(';',[System.StringSplitOptions]::RemoveEmptyEntries) }
  $set=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach($p in $parts){[void]$set.Add($p.Trim())}
  $prepend=[System.Collections.Generic.List[string]]::new()
  foreach($p in $e){ if(-not $set.Contains($p)){ $prepend.Add($p) } }
  if($prepend.Count -gt 0){
    $newPath = ($prepend + $parts) -join ';'
    if($DryRun){ Write-Info "DRYRUN set USER PATH: $($prepend -join ';')" } else { [Environment]::SetEnvironmentVariable('Path',$newPath,'User') }
  }
  # session PATH
  $sessParts=$env:Path.Split(';',[System.StringSplitOptions]::RemoveEmptyEntries)
  $sessSet=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach($p in $sessParts){[void]$sessSet.Add($p.Trim())}
  foreach($p in $e){ if(-not $sessSet.Contains($p)){ if($DryRun){Write-Info "DRYRUN prepend session PATH: $p"} else {$env:Path="$p;$env:Path"} } }
}

function Remove-UserPathEntries([string[]]$e){
  $userPath=[Environment]::GetEnvironmentVariable('Path','User')
  $parts=@(); if($userPath){ $parts=$userPath.Split(';',[System.StringSplitOptions]::RemoveEmptyEntries) }
  $newParts = foreach($p in $parts){ if($e -notcontains $p){ $p } }
  if($DryRun){ Write-Info "DRYRUN remove USER PATH: $($e -join ';')" } else { [Environment]::SetEnvironmentVariable('Path',($newParts -join ';'),'User') }
}

function Copy-Tree($Src,$Dst){
  if(-not (Test-Path $Src)){ Write-Info "Nothing to migrate from $Src"; return }
  Ensure-Directory $Dst
  $excluded=@('cache','npm-cache','_cacache')
  $items=Get-ChildItem -LiteralPath $Src -Force
  foreach($it in $items){
    if($excluded -contains $it.Name){ continue }
    if($it.PSIsContainer -and $it.Name -eq 'node_modules'){
      Write-Info "Copy dir: $($it.FullName) -> $Dst"
      if(-not $DryRun){ Copy-Item -LiteralPath $it.FullName -Destination $Dst -Recurse -Force }
    } elseif($it.Extension -in '.cmd','.ps1'){
      $target=Join-Path $Dst $it.Name
      Write-Info "Copy shim: $($it.FullName) -> $target"
      if(-not $DryRun){ Copy-Item -LiteralPath $it.FullName -Destination $target -Force }
    }
  }
  Ensure-Directory (Join-Path $Dst 'node_modules\.bin')
}

function Update-UserNpmrcPrefix([string]$newPrefix){
    if ($NoUserNpmrc) { Write-Info "Skipping ~/.npmrc write (per -NoUserNpmrc)"; return }
    $line = "prefix=$newPrefix"
    if ($DryRun) {
        Write-Info "DRYRUN write to $UserNpmrcPath -> $line"
        return
    }
    if (Test-Path $UserNpmrcPath) {
        $content = Get-Content $UserNpmrcPath -Raw
        if ($content -match '^\s*prefix\s*=.*$') {
            $updated = ($content -split "`r?`n") | ForEach-Object {
                if ($_ -match '^\s*prefix\s*=.*$') { $line } else { $_ }
            }
            $updated -join "`r`n" | Set-Content -Path $UserNpmrcPath -Encoding UTF8
        } else {
            Add-Content -Path $UserNpmrcPath -Value $line
        }
    } else {
        Set-Content -Path $UserNpmrcPath -Value $line -Encoding UTF8
    }
    Write-Info "Updated user ~/.npmrc with: $line"
}

function Show-Status(){
  $prefixNow=Get-NpmPrefix
  $binNow=Get-NpmBin
  $rootNow=Get-NpmRoot
  Write-Host ""; Write-Step "npm status"
  Write-Host "prefix: $prefixNow"
  Write-Host "bin   : $binNow"
  Write-Host "root  : $rootNow"
  if ($env:NVM_HOME) {
    Write-Host "NVM_HOME   : $($env:NVM_HOME)"
    Write-Host "NVM_SYMLINK: $($env:NVM_SYMLINK)"
  }
  Write-Host ""
}

#----------------- preflight -----------------
if(-not (Get-Command npm -ErrorAction SilentlyContinue)){ Write-Error "npm not found. Install Node.js (or nvm-windows) first."; exit 1 }

$currPrefix = Get-NpmPrefix
$state = Read-State
if(-not $state){ $state=[pscustomobject]@{ originalPrefix = $null } }
if(-not $state.originalPrefix){ Write-Info "Capturing original prefix: $currPrefix"; Write-State -OriginalPrefix $currPrefix; $state=Read-State }

# Decide target prefix
$targetPrefix = if ($Revert) {
  if ($state.originalPrefix) { $state.originalPrefix } else { $DefaultUserNpm }
} else {
  $Prefix
}

if ($Revert) { Write-Step "Reverting npm prefix to: $targetPrefix" }
else         { Write-Step "Setting npm prefix to:   $targetPrefix" }

$targetBin   = Join-Path $targetPrefix 'node_modules\.bin'
$targetCache = Join-Path $targetPrefix 'cache'

Write-Info "Current prefix : $currPrefix"
Write-Info "Target  prefix : $targetPrefix"
Write-Info "Migration source (only when target is C:\Dev): $DefaultUserNpm"

#----------------- create target dirs -----------------
Ensure-Directory $targetPrefix
Ensure-Directory $targetCache
Ensure-Directory $targetBin

#----------------- set npm config -----------------
$ok1=Try-NpmConfigSet 'prefix' $targetPrefix
$ok2=Try-NpmConfigSet 'cache'  $targetCache
if(-not ($ok1 -and $ok2)){ Write-Warning "npm config may not be fully applied; continuing." }

# Persist in user-level ~/.npmrc so it survives nvm-windows version switches
Update-UserNpmrcPrefix -newPrefix $targetPrefix

#----------------- migration logic -----------------
# Only migrate when moving *to* C:\Dev, and only from %APPDATA%\npm
if (-not $Revert -and ($targetPrefix -ieq 'C:\Dev')) {
    if ((Test-Path $DefaultUserNpm) -and ((Resolve-Path $DefaultUserNpm).Path -ine (Resolve-Path $targetPrefix).Path)) {
        Write-Step "Migrating global packages from: $DefaultUserNpm  ->  $targetPrefix"
        Copy-Tree -Src $DefaultUserNpm -Dst $targetPrefix

        if (-not $KeepSource) {
            # Remove old npm user-path entries from PATH after migration
            $removeFromPath = PathPiecesFromPrefix $DefaultUserNpm
            Remove-UserPathEntries -Entries $removeFromPath
        } else {
            Write-Info "Keeping original %APPDATA%\npm entries in PATH (per -KeepSource)"
        }
    } else {
        Write-Info "Migration skipped (no %APPDATA%\npm found or source equals target)."
    }
} else {
    Write-Info "No migration performed (either reverting or target isn't C:\Dev)."
}

#----------------- PATH updates -----------------
$addEntries = PathPiecesFromPrefix $targetPrefix
$removeEntries = @()
if ($currPrefix -and ($currPrefix -ne $targetPrefix)) { $removeEntries += PathPiecesFromPrefix $currPrefix }
# (We may have already removed %APPDATA%\npm above unless -KeepSource was set)

Write-Step "Updating PATH"
Add-UserPathEntries -Entries $addEntries
if ($removeEntries.Count -gt 0) { Remove-UserPathEntries -Entries ($removeEntries | Select-Object -Unique) }

#----------------- validate / test -----------------
Show-Status
if(-not $SkipTest){
  Write-Step "Installing test CLI (cowsay) for validation"
  try{ if(-not $DryRun){ npm install -g cowsay | Out-Null } }catch{ Write-Warning "Could not install 'cowsay': $_" }
  Write-Host "where cowsay ->"
  try{ where cowsay }catch{ Write-Warning "where.exe couldn't find 'cowsay' in PATH" }
  Write-Host ""
  try{ cowsay "npm prefix OK -> $targetPrefix" }catch{ Write-Warning "Running 'cowsay' failed. Open a new terminal and retry." }
}

Write-Host ""
Write-Step "Done"
if ($env:NVM_HOME) {
  Write-Info "nvm-windows detected. The ~/.npmrc prefix makes the setting persist across 'nvm use' switches."
}
Write-Host "Open a new terminal so all processes pick up the updated User PATH."
Write-Host "State file: $StatePath"
