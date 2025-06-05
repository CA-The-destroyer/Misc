<#
.SYNOPSIS
  - Mode 1: Display zonal/non-zonal VM groups with hostnames and let you choose one (or none) to deallocate.
  - Mode 2: Create a single “test” VM in a specified availability zone, with basic networking auto-provisioned (no public IP), using the Azure CLI for VM creation.

.PARAMETER WhatIf
  If present, simulates all Azure calls (prints commands) but does not actually create or deallocate.

.EXAMPLE
  # Simulate everything (no actual changes):
  .\DR-Zone-Manager.ps1 -WhatIf

.EXAMPLE
  # Actually deallocate (interactive selection):
  .\DR-Zone-Manager.ps1

.EXAMPLE
  # Actually create a single test VM (dynamically prompts for zone, RG, etc.) without a public IP:
  .\DR-Zone-Manager.ps1
#>

param(
    [switch]$WhatIf
)

#———————————————————————————————————————————————
# 1) Ensure Azure CLI is installed & you’re logged in
#———————————————————————————————————————————————
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

#———————————————————————————————————————————————
# 2) Prepare a timestamped log file
#———————————————————————————————————————————————
$timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$logFile   = Join-Path $PSScriptRoot "DR-Zone-Manager-$timestamp.log"
"Run started at $(Get-Date -Format 'u')" | Out-File $logFile -Encoding UTF8

#———————————————————————————————————————————————
# 3) Prompt for operation mode
#———————————————————————————————————————————————
Write-Host "`nSelect an operation mode:" -ForegroundColor Cyan
Write-Host "  [1] Deallocate existing VMs by zone/non-zonal/all/none"
Write-Host "  [2] Create a single 'test' VM in a specified availability zone (no public IP)"
Write-Host "  [3] Exit without any action"

do {
    $modeInput = Read-Host "`nEnter choice (1-3)"
} while (-not ($modeInput -as [int] -and $modeInput -ge 1 -and $modeInput -le 3))

if ($modeInput -eq 3) {
    Write-Host "`nExiting (no action taken)." -ForegroundColor Yellow
    "User chose Exit. Exiting at $(Get-Date -Format 'u')." | Out-File -Append $logFile -Encoding UTF8
    exit 0
}

#———————————————————————————————————————————————
# MODE 1: DEALLOCATE EXISTING VMS
#———————————————————————————————————————————————
if ($modeInput -eq 1) {
    # 3a) Fetch all VMs + their Zones property
    try {
        $allVMs = az vm list --show-details `
            --query "[].{Name:name,ResourceGroup:resourceGroup,Zones:zones}" `
            -o json | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to retrieve VMs: $_"
        "ERROR: Failed to list VMs: $($_)" | Out-File -Append $logFile -Encoding UTF8
        exit 1
    }

    if ($null -eq $allVMs -or $allVMs.Count -eq 0) {
        Write-Host "`nNo VMs found in this subscription." -ForegroundColor Green
        "No VMs found. Exiting." | Out-File -Append $logFile -Encoding UTF8
        exit 0
    }

    # 3b) Separate into zonal vs. non-zonal
    $zonalVMs    = $allVMs | Where-Object { $_.Zones -and $_.Zones.Count -gt 0 }
    $nonZonalVMs = $allVMs | Where-Object { -not $_.Zones -or $_.Zones.Count -eq 0 }
    $uniqueZones = $zonalVMs | ForEach-Object { $_.Zones } | ForEach-Object { $_ } | Sort-Object -Unique

    # 4) Build a hashtable grouping VMs by zone
    $zonalGroups = @{}
    foreach ($zone in $uniqueZones) {
        $zonalGroups[$zone] = $zonalVMs | Where-Object { $_.Zones -contains $zone }
    }

    # 5) Display each group with hostnames
    Write-Host "`nSelect which set of VMs to deallocate:`n" -ForegroundColor Cyan

    foreach ($zone in $uniqueZones) {
        Write-Host "Zone $($zone):" -ForegroundColor Yellow
        foreach ($vm in $zonalGroups[$zone]) {
            Write-Host "  - $($vm.Name)"
        }
        Write-Host ""
    }

    Write-Host "Non-Zonal VMs:" -ForegroundColor Yellow
    foreach ($vm in $nonZonalVMs) {
        Write-Host "  - $($vm.Name)"
    }
    Write-Host ""

    Write-Host "All VMs:" -ForegroundColor Yellow
    foreach ($vm in $allVMs) {
        Write-Host "  - $($vm.Name)"
    }
    Write-Host ""

    Write-Host "None:" -ForegroundColor Yellow
    Write-Host "  - (no action)" -ForegroundColor DarkGray
    Write-Host ""

    # 6) Build a numbered menu
    $menu = @()
    foreach ($zone in $uniqueZones) {
        $menu += [PSCustomObject]@{ Label = "Zone $zone"; Targets = $zonalGroups[$zone] }
    }
    $menu += [PSCustomObject]@{ Label = "Non-Zonal VMs"; Targets = $nonZonalVMs }
    $menu += [PSCustomObject]@{ Label = "All VMs";        Targets = $allVMs }
    $menu += [PSCustomObject]@{ Label = "None";           Targets = @() }

    Write-Host "Choices:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $menu.Count; $i++) {
        $count = $menu[$i].Targets.Count
        Write-Host "  [$($i + 1)] $($menu[$i].Label) ($count VMs)"
    }

    do {
        $selection = Read-Host "`nEnter the number of your choice (1-$($menu.Count))"
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
        "VMs targeted: $($targets | ForEach-Object { $_.Name } -join ', ')" |
            Out-File -Append $logFile -Encoding UTF8
    }
    else {
        Write-Host "`n(no VMs will be deallocated)" -ForegroundColor DarkGray
        "No VMs targeted." | Out-File -Append $logFile -Encoding UTF8
    }

    # 8) Double-confirm (unless “None”)
    if ($label -ne 'None') {
        if (-not $WhatIf) {
            $confirm = Read-Host "`nAre you absolutely sure? (Y/N)"
            if ($confirm -notin 'Y','y') {
                Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                "Cancelled at double-confirm." | Out-File -Append $logFile -Encoding UTF8
                exit 0
            }
        }
        else {
            Write-Host "`n(WhatIf mode: no action taken)" -ForegroundColor Yellow
            "(WhatIf mode)" | Out-File -Append $logFile -Encoding UTF8
        }

        # 9) Deallocate each selected VM (async)
        Write-Host ""
        foreach ($vm in $targets) {
            $rg   = $vm.ResourceGroup
            $name = $vm.Name
            $cmd  = "az vm deallocate --resource-group `"$rg`" --name `"$name`" --no-wait"

            if ($WhatIf) {
                Write-Host "WhatIf: $cmd"
                "Would run: $cmd" | Out-File -Append $logFile -Encoding UTF8
            }
            else {
                Write-Host "Running: $cmd"
                try {
                    az vm deallocate --resource-group $rg --name $name --no-wait | Out-Null
                    "Ran: $cmd" | Out-File -Append $logFile -Encoding UTF8
                }
                catch {
                    Write-Host "  [ERROR] Failed to submit deallocation for $($name): $($_)" -ForegroundColor Red
                    "Error deallocating $($name): $($_)" | Out-File -Append $logFile -Encoding UTF8
                }
            }
        }

        Write-Host "`nDeallocation commands submitted." -ForegroundColor Green
        "Run completed at $(Get-Date -Format 'u')" | Out-File -Append $logFile -Encoding UTF8
    }
    else {
        Write-Host "`nNo action taken." -ForegroundColor Green
        "None selected - no deallocation." | Out-File -Append $logFile -Encoding UTF8
    }

    Write-Host "`nLog file saved at: $logFile" -ForegroundColor Cyan
    exit 0
} # End of Mode 1

#———————————————————————————————————————————————
# MODE 2: CREATE A SINGLE TEST VM IN A SPECIFIED ZONE (NO PUBLIC IP)
#      Uses Azure CLI 'az vm create' for VM creation
#———————————————————————————————————————————————
elseif ($modeInput -eq 2) {
    Write-Host "`n** Creating a test VM (no public IP) **`n" -ForegroundColor Cyan

    #
    # 2a) Prompt for core VM settings
    #
    # The script will:
    #   • Ask for an existing Resource Group (or create one)
    #   • Prompt for VM name, zone (1/2/3), size, image alias, admin credentials
    #   • Auto-create a VNet/Subnet (10.0.0.0/16 → 10.0.0.0/24) and a NIC in that subnet
    #   • Then call 'az vm create' with --nics and --zone to place the VM accordingly
    #

    # 2a.1) Resource Group
    do {
        $rgName = Read-Host "Enter the Resource Group name in which to create the VM"
    } while ([string]::IsNullOrWhiteSpace($rgName))

    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
    if (-not $rg) {
        $createRG = Read-Host "Resource Group '$rgName' does not exist. Create it? (Y/N)"
        if ($createRG -in 'Y','y') {
            do {
                $location = Read-Host "Enter the Azure region (e.g. eastus, westus2) for the new Resource Group"
            } while ([string]::IsNullOrWhiteSpace($location))

            if ($WhatIf) {
                $cmd = "az group create --name `"$rgName`" --location `"$location`" --output none --what-if"
                Write-Host "`nWhatIf: $cmd"
                "Would run: $cmd" | Out-File -Append $logFile -Encoding UTF8
            }
            else {
                Write-Host "`nCreating Resource Group '$rgName' in '$location'..." -ForegroundColor Yellow
                try {
                    az group create --name $rgName --location $location --output none
                    Write-Host "Resource Group '$rgName' created." -ForegroundColor Green
                    "Created Resource Group: $rgName in $location" | Out-File -Append $logFile -Encoding UTF8
                }
                catch {
                    Write-Error "Failed to create Resource Group: $($_)"
                    "ERROR: Failed to create Resource Group $($rgName): $($_)" | Out-File -Append $logFile -Encoding UTF8
                    exit 1
                }
            }
        }
        else {
            Write-Error "Resource Group '$rgName' does not exist, and user declined creation. Exiting."
            "Exiting: RG not found and user refused creation." | Out-File -Append $logFile -Encoding UTF8
            exit 1
        }
    }
    else {
        $location = $rg.Location
        Write-Host "Resource Group '$rgName' exists in region '$location'." -ForegroundColor Green
        "Using existing RG: $rgName (Location: $location)" | Out-File -Append $logFile -Encoding UTF8
    }

    # 2a.2) VM Name
    do {
        $vmName = Read-Host "Enter a name for the new test VM (e.g. 'TestVM-01')"
    } while ([string]::IsNullOrWhiteSpace($vmName))

    # 2a.3) Location is already captured as $location

    # 2a.4) Availability Zone
    Write-Host "`nAvailable zones are typically '1','2','3' in this region." -ForegroundColor Yellow
    do {
        $zoneChoice = Read-Host "Enter the Availability Zone number (just the digit, e.g. '1')"
    } while (-not ($zoneChoice -match '^[1-3]$'))

    # 2a.5) VM Size (default)
    $defaultSize = "Standard_DS1_v2"
    do {
        $vmSize = Read-Host "Enter VM size [default: $defaultSize]"
        if ([string]::IsNullOrWhiteSpace($vmSize)) {
            $vmSize = $defaultSize
        }
    } while ([string]::IsNullOrWhiteSpace($vmSize))

    # 2a.6) Image (alias or publisher:offer:sku:version)
    $defaultImage = "Win2019Datacenter"
    do {
        $imageInput = Read-Host "Enter a valid Image alias/name [default: $defaultImage]"
        if ([string]::IsNullOrWhiteSpace($imageInput)) {
            $imageInput = $defaultImage
        }
    } while ([string]::IsNullOrWhiteSpace($imageInput))

    # 2a.7) Admin Username & Password
    do {
        $adminUser = Read-Host "Enter the admin username for the VM"
    } while ([string]::IsNullOrWhiteSpace($adminUser))

    do {
        $adminPassword = Read-Host "Enter the admin password (min 12 chars, complex)" -AsSecureString
        $plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword))
    } while ($plainPwd.Length -lt 12)

    # Store plain password for CLI
    $pwdPlain = $plainPwd

    #
    # 2b) Create VNet/Subnet and NIC (no public IP)
    #
    $vnetName   = "$vmName-VNet"
    $subnetName = "Subnet1"
    $nicName    = "$vmName-NIC"

    # VNet + Subnet
    $existingVNet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $existingVNet) {
        if ($WhatIf) {
            $cmd = "az network vnet create --resource-group `"$rgName`" --name `"$vnetName`" `
                    --address-prefix 10.0.0.0/16 --subnet-name `"$subnetName`" --subnet-prefix 10.0.0.0/24 --output none --what-if"
            Write-Host "`nWhatIf: $cmd"
            "Would run: $cmd" | Out-File -Append $logFile -Encoding UTF8
        }
        else {
            Write-Host "`nCreating Virtual Network '$vnetName' with Subnet '$subnetName'..." -ForegroundColor Yellow
            try {
                az network vnet create `
                    --resource-group $rgName `
                    --name $vnetName `
                    --address-prefix 10.0.0.0/16 `
                    --subnet-name $subnetName `
                    --subnet-prefix 10.0.0.0/24 `
                    --output none

                Write-Host "Virtual Network '$vnetName' created." -ForegroundColor Green
                "Created VNet: $vnetName with Subnet: $subnetName" | Out-File -Append $logFile -Encoding UTF8
            }
            catch {
                Write-Error "Failed to create VNet/Subnet: $($_)"
                "ERROR: Failed to create VNet/Subnet: $($_)" | Out-File -Append $logFile -Encoding UTF8
                exit 1
            }
        }
    }
    else {
        Write-Host "VNet '$vnetName' already exists. Skipping creation." -ForegroundColor Yellow
        "Skipped VNet creation; '$vnetName' exists." | Out-File -Append $logFile -Encoding UTF8
    }

    # NIC (no Public IP)
    $existingNic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $existingNic) {
        if ($WhatIf) {
            $cmd = "az network nic create --resource-group `"$rgName`" --name `"$nicName`" `
                    --vnet-name `"$vnetName`" --subnet `"$subnetName`" --output none --what-if"
            Write-Host "`nWhatIf: $cmd"
            "Would run: $cmd" | Out-File -Append $logFile -Encoding UTF8
        }
        else {
            Write-Host "`nCreating Network Interface '$nicName' (no public IP)..." -ForegroundColor Yellow
            try {
                az network nic create `
                    --resource-group $rgName `
                    --name $nicName `
                    --vnet-name $vnetName `
                    --subnet $subnetName `
                    --output none

                Write-Host "Network Interface '$nicName' created." -ForegroundColor Green
                "Created NIC (no public IP): $nicName" | Out-File -Append $logFile -Encoding UTF8
            }
            catch {
                Write-Error "Failed to create NIC: $($_)"
                "ERROR: Failed to create NIC: $($_)" | Out-File -Append $logFile -Encoding UTF8
                exit 1
            }
        }
    }
    else {
        Write-Host "NIC '$nicName' already exists. Skipping creation." -ForegroundColor Yellow
        "Skipped NIC creation; '$nicName' exists." | Out-File -Append $logFile -Encoding UTF8
    }

    # Retrieve NIC ID
    $nicObj = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName

    #
    # 2c) Create the VM using Azure CLI with --nics and --zone
    #
    Write-Host "`nAbout to create VM '$vmName' in Zone '$zoneChoice' (no public IP)..." -ForegroundColor Cyan

    $cliCmd = @(
        "az vm create",
        "--resource-group `"$rgName`"",
        "--name `"$vmName`"",
        "--image `"$imageInput`"",
        "--size `"$vmSize`"",
        "--nics `"$($nicObj.Id)`"",
        "--zone `"$zoneChoice`"",
        "--admin-username `"$adminUser`"",
        "--admin-password `"$pwdPlain`"",
        "--no-wait",
        "--output none"
    ) -join " "

    if ($WhatIf) {
        Write-Host "`nWhatIf: $cliCmd"
        "Would run CLI: $cliCmd" | Out-File -Append $logFile -Encoding UTF8
    }
    else {
        try {
            Invoke-Expression $cliCmd
            Write-Host "`nVM '$vmName' creation in Zone '$zoneChoice' submitted." -ForegroundColor Green
            "Ran CLI: $cliCmd" | Out-File -Append $logFile -Encoding UTF8
        }
        catch {
            Write-Error "Failed to create VM '$vmName': $($_)"
            "ERROR: Failed to run CLI '$cliCmd': $($_)" | Out-File -Append $logFile -Encoding UTF8
            exit 1
        }
    }

    Write-Host "`nLog file saved at: $logFile" -ForegroundColor Cyan
    exit 0
}
