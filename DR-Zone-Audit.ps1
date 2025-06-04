# ***Zone Audit***CA

# 1. Log in and select subscription
# --------------------------------------------------------
# 1. Prompt for required info
# --------------------------------------------------------
$subscription = Read-Host "Enter Azure subscription ID (or name)"
$outputPath   = Read-Host "Enter full path for output CSV (e.g. C:\Temp\ZoneAudit.csv)"

# --------------------------------------------------------
# 2. Log in & set subscription
# --------------------------------------------------------
az login | Out-Null
az account set --subscription $subscription

# --------------------------------------------------------
# 3. Define and run the Resource Graph query (all properties)
# --------------------------------------------------------
#    This query returns every field that ARG knows about,
#    including id, name, type, location, resourceGroup, subscriptionId,
#    tenantId, properties (full JSON), tags, sku, kind, managedBy, etc.
$query = @"
Resources
| where isnotempty(properties['zones'])
"@

# Increase --first if you believe you have > 5000 zone-enabled assets
$jsonResult = az graph query -q $query --first 50000 --output json

# --------------------------------------------------------
# 4. Convert JSON → PowerShell objects → CSV
# --------------------------------------------------------
#    The JSON from 'az graph query' has the shape: { "data": [ { … }, { … }, … ] }
#    So we ConvertFrom-Json, then take .data, then write it all to CSV.
$data = $jsonResult | ConvertFrom-Json | Select-Object -ExpandProperty data

$data | Export-Csv -Path $outputPath -NoTypeInformation

# --------------------------------------------------------
# 5. Confirmation
# --------------------------------------------------------
Write-Host "`nExport complete. File written to:`n$outputPath"


