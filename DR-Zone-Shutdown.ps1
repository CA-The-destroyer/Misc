<#
.SYNOPSIS
  Display zonal/non-zonal VM groups with hostnames and let you choose one (or none) to deallocate.

.PARAMETER WhatIf
  If present, simulates the run (prints commands) but does not actually deallocate.
#>

param(
    [switch]$WhatIf
)

# 1) Ensure Azure CLI is installed and you’re logged in
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI ('az') not found. Install from https://aka.ms/install-azure-cli"
    exit 1
}
try {
    az account show --output none 2>$null
}
catch {
    Write-Host "Logging into Azure..." -ForegroundColor Yellow
    az login | Out-Null
}

# 2) Prepare log file
$logFile = Join-Path $PSScriptRoot "DR-Zone-Shutdown-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
"Run started at $(Get-Date)" | Out-File $logFile -Encoding UTF8

# 3) Fetch all VMs + their zone info
$allVMs = az vm list --show-details `
    --query "[].{Name:name,ResourceGroup:resourceGroup,Zones:zones}" `
    -o json |
  ConvertFrom-Json

if ($allVMs.Count -eq 0) {
    Write-Host "No VMs found in this subscription." -ForegroundColor Green
    "No VMs found, exiting." | Out-File -Append $logFile
    exit 0
}

# 4) Build zone groups and non-zonal list
$uniqueZones = $allVMs |
    Where-Object { $_.Zones } |
    ForEach-Object { $_.Zones } |
    ForEach-Object { $_ } |
    Sort-Object -Unique

$zonalGroups = @{}
foreach ($zone in $uniqueZones) {
    $zonalGroups[$zone] = $allVMs | Where-Object { $_.Zones -contains $zone }
}
$nonZonal = $allVMs | Where-Object { -not $_.Zones -or $_.Zones.Count -eq 0 }

# 5) Display every group with hostnames
Write-Host "`nSelect which set of VMs to deallocate:" -ForegroundColor Cyan

foreach ($zone in $uniqueZones) {
    Write-Host "`nZone $($zone):" -ForegroundColor Yellow
    foreach ($vm in $zonalGroups[$zone]) {
        Write-Host "  - $($vm.Name)"
    }
}

Write-Host "`nNon-Zonal VMs:" -ForegroundColor Yellow
foreach ($vm in $nonZonal) {
    Write-Host "  - $($vm.Name)"
}

Write-Host "`nAll VMs:" -ForegroundColor Yellow
foreach ($vm in $allVMs) {
    Write-Host "  - $($vm.Name)"
}

Write-Host "`nNone:" -ForegroundColor Yellow
Write-Host "  - (no action)" -ForegroundColor DarkGray

# 6) Build a numbered menu for selection
$menu = @()
foreach ($zone in $uniqueZones) {
    $menu += [PSCustomObject]@{ Label = "Zone $zone"; Targets = $zonalGroups[$zone] }
}
$menu += [PSCustomObject]@{ Label = "Non-Zonal VMs"; Targets = $nonZonal }
$menu += [PSCustomObject]@{ Label = "All VMs";       Targets = $allVMs }
$menu += [PSCustomObject]@{ Label = "None";          Targets = @() }

Write-Host "`nChoices:" -ForegroundColor Cyan
for ($i = 0; $i -lt $menu.Count; $i++) {
    Write-Host "  [$($i+1)] $($menu[$i].Label) ($($menu[$i].Targets.Count) VMs)"
}

do {
    $selection = Read-Host "Enter the number of your choice (1-$($menu.Count))"
} while (-not ($selection -as [int] -and $selection -ge 1 -and $selection -le $menu.Count))

$choiceObj = $menu[[int]$selection - 1]
$label     = $choiceObj.Label
$targets   = $choiceObj.Targets

Write-Host "`nYou selected: $label" -ForegroundColor Green
"Selection: $label" | Out-File -Append $logFile -Encoding UTF8

# 7) Show exactly which VMs are in that selection
if ($targets.Count -gt 0) {
    Write-Host "`nVMs in this selection:" -ForegroundColor Cyan
    foreach ($vm in $targets) {
        Write-Host "  - $($vm.Name) (RG: $($vm.ResourceGroup))"
    }
    "VMs: $($targets | ForEach-Object { $_.Name } -join ', ')" |
        Out-File -Append $logFile -Encoding UTF8
} else {
    Write-Host "`n(no VMs will be deallocated)" -ForegroundColor DarkGray
    "No VMs targeted." | Out-File -Append $logFile -Encoding UTF8
}

# 8) Double-confirm (unless 'None')
if ($label -ne 'None') {
    if (-not $WhatIf) {
        $confirm = Read-Host "`nAre you absolutely sure? (Y/N)"
        if ($confirm -notin 'Y','y') {
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            "Cancelled at double-confirm." | Out-File -Append $logFile -Encoding UTF8
            exit 0
        }
    } else {
        Write-Host "`n(WhatIf mode: no action taken)" -ForegroundColor Yellow
        "(WhatIf mode)" | Out-File -Append $logFile -Encoding UTF8
    }

    # 9) Deallocate each selected VM
    foreach ($vm in $targets) {
        $cmd = "az vm deallocate --resource-group $($vm.ResourceGroup) --name $($vm.Name) --no-wait"
        if ($WhatIf) {
            Write-Host "Would run: $cmd"
            "Would run: $cmd" | Out-File -Append $logFile -Encoding UTF8
        } else {
            Write-Host "Running: $cmd"
            az vm deallocate --resource-group $vm.ResourceGroup --name $vm.Name --no-wait | Out-Null
            "Ran: $cmd" | Out-File -Append $logFile -Encoding UTF8
        }
    }

    Write-Host "`nDeallocation commands submitted." -ForegroundColor Green
    "Run completed at $(Get-Date)" | Out-File -Append $logFile -Encoding UTF8
} else {
    Write-Host "`nNo action taken." -ForegroundColor Green
    "None selected - no deallocation." | Out-File -Append $logFile -Encoding UTF8
}

# 10) Final message
Write-Host "`nLog file saved at: $logFile" -ForegroundColor Cyan
