# 0) Prereqs
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.SecurityProtocolType]::Tls12 -bor `
    [Net.SecurityProtocolType]::Tls13
Add-Type -AssemblyName System.Net.Http

# 1) Credentials
$orgId  = 'orgid'
$apiKey = 'apikey'

# Debug prefixes
Write-Host "Org: $($orgId.Substring(0,8))…"
Write-Host "Key: $($apiKey.Substring(0,8))…"

# 2) HttpClient + headers
$client = [System.Net.Http.HttpClient]::new()
$client.DefaultRequestHeaders.Authorization = `
  [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $apiKey)
$client.DefaultRequestHeaders.Add('X-Auth-Organization-Id', $orgId)
$client.DefaultRequestHeaders.Accept.Clear()
$client.DefaultRequestHeaders.Accept.Add(
  [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json')
)

# ←── HERE’S THE CHANGE ──→
$base = 'https://api.controlup.com/api/data'

# List the indices
$response = $client.GetAsync($base).Result
$raw      = $response.Content.ReadAsStringAsync().Result

if (-not $response.IsSuccessStatusCode) {
    Write-Host "❌ HTTP $($response.StatusCode): $($response.ReasonPhrase)"
    Write-Host $raw.Substring(0,200)
    exit 1
}

# Clean & parse
$clean = $raw.TrimStart(" .`r`n`t")
$idx   = $clean.IndexOfAny(@('{','[')); if ($idx -gt 0) { $clean = $clean.Substring($idx) }
$data  = $clean | ConvertFrom-Json

# Show & save
$data | Select-Object name | Format-Table
$data | ConvertTo-Json -Depth 5 | Set-Content data_indices.json -Encoding utf8

# 4) Find license index
$licIndex = ($data | Where-Object { $_.name -match 'license' }).name
if (-not $licIndex) {
  Write-Host "⚠️ No license index found."
  exit 1
}
Write-Host "Using index: $licIndex"

# 5) Search payload
$payload = @{
  timeRange    = @{ from = "now-24h"; to = "now" }
  aggregations = @(@{ type = "max"; field = "peakUsage" })
} | ConvertTo-Json

# 6) POST search
$resp2 = $client.PostAsync(
  "$base/$licIndex/search",
  [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, 'application/json')
).Result
$raw2 = $resp2.Content.ReadAsStringAsync().Result

if (-not $resp2.IsSuccessStatusCode) {
  Write-Host "❌ Search Error $($resp2.StatusCode): $($resp2.ReasonPhrase)"
  Write-Host $raw2.Substring(0,200)
  exit 1
}

# Clean, parse, save
$clean2 = $raw2.TrimStart(" .`r`n`t")
$idx2   = $clean2.IndexOfAny(@('{','[')); if ($idx2 -gt 0) { $clean2 = $clean2.Substring($idx2) }
$licData= $clean2 | ConvertFrom-Json

Set-Content license_clean.json $clean2 -Encoding utf8
$licData.aggregations | Export-Csv license_aggregations.csv -NoTypeInformation
$licData.records      | Export-Csv license_timeseries.csv     -NoTypeInformation

Write-Host "✅ License data written to JSON/CSV files."
