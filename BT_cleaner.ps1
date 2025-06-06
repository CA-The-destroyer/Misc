<#
.SYNOPSIS
    List paired Bluetooth peripherals and force-remove (unpair) the one you choose, using pnputil.exe,
    with fallback to disabling the device if initial removal returns EXIT CODE 5 (Access Denied).

.DESCRIPTION
    • Retrieves all PnP devices in the Bluetooth class via Get-PnpDevice.
    • Filters out non‐peripheral entries (only shows BTHENUM\… devices with a FriendlyName).
    • Displays each device with an index, FriendlyName, Status, and InstanceId.
    • Prompts the user to pick a device to remove (0 = exit).
    • Attempts to remove via:
         pnputil.exe /remove-device "<InstanceId>" /force
      If pnputil exits with code 5 (access denied), it next tries:
         pnputil.exe /disable-device "<InstanceId>"
      then retries remove (/remove-device "<InstanceId>" /force).
    • Must be run as Administrator, or pnputil will return access‐denied errors.

.NOTES
    • Tested on Windows 10/11 with PowerShell 5.1+. Launch PowerShell as “Run as Administrator.”
    • If removal still fails after disable, script reports final exit code and pnputil output.
#>

#------------------------------------------
# 1) Function to list only actual paired Bluetooth peripherals
#------------------------------------------
Function Get-BTDevice {
    <#
    .OUTPUTS
        PSCustomObject with properties:
          • Index        [int]     – menu index
          • FriendlyName [string]  – nonempty
          • Status       [string]
          • InstanceId   [string]  – e.g. BTHENUM\{…}
    #>
    $all = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue
    if (-not $all) {
        return @()
    }

    $index = 0
    foreach ($dev in $all) {
        # Only show entries with a FriendlyName AND whose InstanceId begins with "BTHENUM\"
        if (
            ($dev.FriendlyName -ne $null -and $dev.FriendlyName.Trim().Length -gt 0) -and
            ($dev.InstanceId -like 'BTHENUM\*')
        ) {
            $index++
            [PSCustomObject]@{
                Index        = $index
                FriendlyName = $dev.FriendlyName
                Status       = $dev.Status
                InstanceId   = $dev.InstanceId
            }
        }
    }
}

#------------------------------------------
# 2) Main loop: enumerate, prompt, attempt remove, fallback to disable+remove
#------------------------------------------
do {
    $BTDevices = @( Get-BTDevice )    # Force array even if zero items

    if ($BTDevices.Count -gt 0) {
        Write-Host "`n******** Paired Bluetooth Devices ********`n"
        foreach ($item in $BTDevices) {
            # Format: "  1 - My Headset (OK)  InstanceId: BTHENUM\…"
            ("{0,3} - {1} ({2})  InstanceId: {3}" -f 
               $item.Index, 
               $item.FriendlyName, 
               $item.Status, 
               $item.InstanceId
            ) | Write-Host
        }

        $selected = Read-Host "`nSelect a device number to remove (0 to Exit)"
        if ($selected -notmatch '^[0-9]+$') {
            Write-Host "Invalid input. Please enter a numeric value." -ForegroundColor Red
            continue
        }

        $selInt = [int]$selected
        if ($selInt -eq 0) {
            break
        }
        elseif ($selInt -ge 1 -and $selInt -le $BTDevices.Count) {
            $device   = $BTDevices | Where-Object { $_.Index -eq $selInt }
            $instance = $device.InstanceId

            Write-Host "`nRemoving device:`n  $($device.FriendlyName)" `
                      -NoNewline
            Write-Host " (InstanceId: $instance)" -ForegroundColor Yellow

            #
            # Attempt #1: force-remove
            #
            $output1   = & pnputil.exe /remove-device "$instance" /force 2>&1
            $exitCode1 = $LASTEXITCODE

            if ($exitCode1 -eq 0) {
                Write-Host "→ Device removed successfully." -ForegroundColor Green
            }
            elseif ($exitCode1 -eq 5) {
                # Exit code 5 = Access Denied (often device in use). Try disable then remove.
                Write-Host "→ Initial remove exited with code 5 (Access Denied). Attempting to disable first…" -ForegroundColor Yellow

                #
                # Attempt #2: disable-device
                #
                $disableOut   = & pnputil.exe /disable-device "$instance" 2>&1
                $disableCode  = $LASTEXITCODE

                if ($disableCode -eq 0) {
                    Write-Host "→ Device disabled successfully. Retrying removal…" -ForegroundColor Yellow

                    #
                    # Attempt #3: force-remove again
                    #
                    $output2   = & pnputil.exe /remove-device "$instance" /force 2>&1
                    $exitCode2 = $LASTEXITCODE

                    if ($exitCode2 -eq 0) {
                        Write-Host "→ Device removed successfully after disable." -ForegroundColor Green
                    }
                    else {
                        Write-Host "→ ERROR: Removal still failed with code $exitCode2 after disable." -ForegroundColor Red
                        if ($output2) {
                            "`npnputil.exe output (2nd remove):`n$output2" | Write-Host
                        }
                    }
                }
                else {
                    Write-Host "→ ERROR: Failed to disable device. pnputil exit code $disableCode." -ForegroundColor Red
                    if ($disableOut) {
                        "`npnputil.exe output (disable):`n$disableOut" | Write-Host
                    }
                }
            }
            else {
                Write-Host "→ ERROR: pnputil.exe exited with code $exitCode1." -ForegroundColor Red
                if ($output1) {
                    "`npnputil.exe output (initial remove):`n$output1" | Write-Host
                }
            }

            # Pause briefly so the result is readable before menu redraw
            Start-Sleep -Milliseconds 500
        }
        else {
            Write-Host "Invalid selection. Please enter a number between 0 and $($BTDevices.Count)." `
                      -ForegroundColor Red
        }
    }
    else {
        Write-Host "`n********* No (paired) Bluetooth devices found *********" -ForegroundColor DarkYellow
        break
    }

} while ($true)

Write-Host "`nScript complete. Press any key to exit..." -NoNewline
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
