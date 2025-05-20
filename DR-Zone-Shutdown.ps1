<#
.SYNOPSIS
  Interactively choose an Availability Zone and deallocate all VMs in it, using Azure CLI.

.PARAMETER WhatIf
  If supplied, lists everything and shows the CLI commands, but does not actually call deallocate.
#>

param(
    [switch]$WhatIf
)

# 1) Ensure Azure CLI is installed and you’re logged in
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI ('az') not found. Install it from https://aka.ms/install-azure-cli"
    exit 1
}
try {
    az account show --output none 2>$null
} catch {
    Write-Host "Logging in to Azure…" -ForegroundColor Yellow
    az login | Out-Null
}

# 2) Fetch all VMs with their zones
$allVMs = az vm list --show-details `
    --query "[].{Name:name,ResourceGroup:resourceGroup,Zones:zones}" `
    -o json |
  ConvertFrom-Json

# 3) Build a unique list of non-empty zones
$allZones = $allVMs |
    Where-Object { $_.Zones } |
    ForEach-Object { $_.Zones } |
    ForEach-Object { $_ } |
    Sort-Object -Unique

if ($allZones.Count -eq 0) {
    Write-Host "No zonal VMs found in this subscription." -ForegroundColor Green
    exit 0
}

# 4) Prompt user to select a zone
Write-Host "Available Zones with VMs:" -ForegroundColor Cyan
for ($i = 0; $i -lt $allZones.Count; $i++) {
    Write-Host "  [$($i+1)] Zone $($allZones[$i])"
}

do {
    $selection = Read-Host "Enter the number of the zone to deallocate VMs from"
} while (-not ($selection -as [int] -and $selection -ge 1 -and $selection -le $allZones.Count))

$zone = $allZones[[int]$selection - 1]
Write-Host "→ Selected Zone: $zone" -ForegroundColor Green

# 5) Filter VMs in that zone and list them
$targets = $allVMs | Where-Object { $_.Zones -contains $zone }

Write-Host "`nThe following $($targets.Count) VM(s) will be deallocated:" -ForegroundColor Cyan
foreach ($vm in $targets) {
    Write-Host " • $($vm.Name) (RG: $($vm.ResourceGroup))"
}

# 6) Confirm (skip in WhatIf)
if (-not $WhatIf) {
    $confirm = Read-Host "`nProceed with deallocation? (Y/N)"
    if ($confirm -notin 'Y','y') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "`n(WhatIf mode: no VMs will actually be deallocated)" -ForegroundColor Yellow
}

# 7) Deallocate each VM
foreach ($vm in $targets) {
    $cmd = "az vm deallocate --resource-group $($vm.ResourceGroup) --name $($vm.Name) --no-wait"
    if ($WhatIf) {
        Write-Host "Would run: $cmd"
    }
    else {
        Write-Host "Running: $cmd"
        az vm deallocate --resource-group $vm.ResourceGroup --name $vm.Name --no-wait | Out-Null
    }
}

Write-Host "`nAll commands have been submitted." -ForegroundColor Green
