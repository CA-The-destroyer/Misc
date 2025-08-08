<#
Manage npm global prefix on Windows 11: relocate, migrate from C:\Dev, validate, and revert.

Examples:
  .\NPM_Path_Change.ps1                           # Migrate from C:\Dev to C:\Dev (migration skipped if same)
  .\NPM_Path_Change.ps1 -KeepSource               # Keep files in C:\Dev after migration
  .\NPM_Path_Change.ps1 -Revert                   # Move back to original prefix
  .\NPM_Path_Change.ps1 -DryRun                   # No changes, just showing what it will do. 
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$Prefix = 'C:\Dev',
    [switch]$Revert,
    [switch]$SkipTest,
    [switch]$DryRun,
    [switch]$KeepSource
)

#----------------- constants -----------------
$MigrationSource = 'C:\Dev'
$StateDir  = Join-Path $env:LOCALAPPDATA 'NpmPrefixMgr'
$StatePath = Join-Path $StateDir 'state.json'

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

# --- robust bin resolver (works even if `npm bin -g` isn't supported) ---
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
        # Older npm on Windows often drops shims right in the prefix folder
        if (Test-Path $pref) { return $pref }
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
function Remove-Migrated($Src){
  if(-not (Test-Path $Src)){ return }
  foreach($name in @('node_modules')){ $p=Join-Path $Src $name; if(Test-Path $p){ Write-Info "Remove migrated dir: $p"; if(-not $DryRun){ Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue } } }
  Get-ChildItem -LiteralPath $Src -Filter *.cmd -File -ErrorAction SilentlyContinue | % { Write-Info "Remove shim: $($_.FullName)"; if(-not $DryRun){ Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } }
  Get-ChildItem -LiteralPath $Src -Filter *.ps1 -File -ErrorAction SilentlyContinue | % { Write-Info "Remove shim: $($_.FullName)"; if(-not $DryRun){ Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } }
}
function Show-Status(){
  $prefixNow=Get-NpmPrefix
  $binNow=Get-NpmBin
  $rootNow=Get-NpmRoot
  Write-Host ""; Write-Step "npm status"
  Write-Host "prefix: $prefixNow"
  Write-Host "bin   : $binNow"
  Write-Host "root  : $rootNow"
  Write-Host ""
}

#----------------- preflight -----------------
if(-not (Get-Command npm -ErrorAction SilentlyContinue)){ Write-Error "npm not found. Install Node.js (or nvm-windows) first."; exit 1 }

$currPrefix = Get-NpmPrefix
$state = Read-State
if(-not $state){ $state=[pscustomobject]@{ originalPrefix = $null } }
if(-not $state.originalPrefix){ Write-Info "Capturing original prefix: $currPrefix"; Write-State -OriginalPrefix $currPrefix; $state=Read-State }

# Determine target prefix
if($Revert){
  $targetPrefix = if($state.originalPrefix){ $state.originalPrefix } else { Join-Path $env:APPDATA 'npm' }
  Write-Step "Reverting npm prefix to: $targetPrefix"
} else {
  $targetPrefix = $Prefix
  Write-Step "Setting npm prefix to: $targetPrefix"
}

$targetBin   = Join-Path $targetPrefix 'node_modules\.bin'
$targetCache = Join-Path $targetPrefix 'cache'

Write-Info "Current prefix : $currPrefix"
Write-Info "Target  prefix : $targetPrefix"
Write-Info "Migration src  : $MigrationSource"

#----------------- create target dirs -----------------
Ensure-Directory $targetPrefix
Ensure-Directory $targetCache
Ensure-Directory $targetBin

#----------------- set npm config -----------------
$ok1=Try-NpmConfigSet 'prefix' $targetPrefix
$ok2=Try-NpmConfigSet 'cache'  $targetCache
if(-not ($ok1 -and $ok2)){ Write-Warning "npm config may not be fully applied; continuing." }

#----------------- migrate from hard-coded path -----------------
if ( (Test-Path $MigrationSource) -and ($MigrationSource -ne $targetPrefix) ) {
  Write-Step "Migrating from: $MigrationSource"
  Copy-Tree -Src $MigrationSource -Dst $targetPrefix
  if(-not $KeepSource){ Remove-Migrated -Src $MigrationSource }
} else {
  Write-Info "Migration skipped (source missing or same as target)."
}

#----------------- PATH updates -----------------
$addEntries    = PathPiecesFromPrefix $targetPrefix
$removeEntries = if($currPrefix -and ($currPrefix -ne $targetPrefix)){ PathPiecesFromPrefix $currPrefix } else { @() }
Write-Step "Updating PATH"
Add-UserPathEntries -Entries $addEntries
if($removeEntries.Count -gt 0){ Remove-UserPathEntries -Entries $removeEntries }

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
Write-Host "Open a new terminal so all processes pick up the updated User PATH."
Write-Host "State file: $StatePath"
