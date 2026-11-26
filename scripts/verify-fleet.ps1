[CmdletBinding()]
param(
    [string]$HostAddress = $(if ($env:MW_VERIFY_HOST) { $env:MW_VERIFY_HOST } else { "127.0.0.1" }),
    [int]$TimeoutSec = $(if ($env:MW_VERIFY_TIMEOUT) { [int]$env:MW_VERIFY_TIMEOUT } else { 3 })
)

$ErrorActionPreference = "Stop"

function Resolve-ServiceUrl {
    param(
        [string]$UrlEnv,
        [string]$PortEnv,
        [int]$DefaultPort
    )
    $explicit = [Environment]::GetEnvironmentVariable($UrlEnv)
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        return $explicit.TrimEnd('/')
    }
    $portVal = [Environment]::GetEnvironmentVariable($PortEnv)
    $port = if (-not [string]::IsNullOrWhiteSpace($portVal)) { $portVal } else { $DefaultPort }
    return "http://${HostAddress}:${port}"
}

$services = @(
    @{ Name = "mw-echo";    Url = Resolve-ServiceUrl "MW_ECHO_URL"    "MW_ECHO_PORT"    4310 }
    @{ Name = "mw-lab";     Url = Resolve-ServiceUrl "MW_LAB_URL"     "MW_LAB_PORT"     4400 }
    @{ Name = "mw-mission"; Url = Resolve-ServiceUrl "MW_MISSION_URL" "MW_MISSION_PORT" 4410 }
    @{ Name = "mw-dock";    Url = Resolve-ServiceUrl "MW_DOCK_URL"    "MW_DOCK_PORT"    3000 }
    @{ Name = "mw-design";  Url = Resolve-ServiceUrl "MW_DESIGN_URL"  "MW_DESIGN_PORT"  8080 }
    @{ Name = "mw-isp";     Url = Resolve-ServiceUrl "MW_ISP_URL"     "MW_ISP_PORT"     8091 }
    @{ Name = "mw-cp";      Url = Resolve-ServiceUrl "MW_CP_URL"      "MW_CP_PORT"      4440 }
    @{ Name = "mw-corpus";  Url = Resolve-ServiceUrl "MW_CORPUS_URL"  "MW_CORPUS_PORT"  4420 }
    @{ Name = "mw-nexus";   Url = Resolve-ServiceUrl "MW_NEXUS_URL"   "MW_NEXUS_PORT"   4430 }
    @{ Name = "mw-lore";    Url = Resolve-ServiceUrl "MW_LORE_URL"    "MW_LORE_PORT"    4450 }
    @{ Name = "mw-mylove";  Url = Resolve-ServiceUrl "MW_MYLOVE_URL"  "MW_MYLOVE_PORT"  4460 }
    @{ Name = "mw-studio";  Url = Resolve-ServiceUrl "MW_STUDIO_URL"  "MW_STUDIO_PORT"  4470 }
    @{ Name = "mw-rid";     Url = Resolve-ServiceUrl "MW_RID_URL"     "MW_RID_PORT"     4480 }
)

$ridBaseUrl = Resolve-ServiceUrl "MW_RID_URL" "MW_RID_PORT" 4480
$contracts = @(
    @{ Name = "mw-rid-oidc"; Endpoint = "$ridBaseUrl/.well-known/openid-configuration" }
)

Write-Output ("{0,-14} {1,-8} {2,-6} {3,-10} {4}" -f "SERVICE", "STATUS", "HTTP", "LATENCY", "ENDPOINT")
Write-Output ("{0,-14} {1,-8} {2,-6} {3,-10} {4}" -f "--------------", "--------", "------", "----------", "----------------------------------")

$okCount = 0
$totalCount = $services.Count + $contracts.Count

function Test-FleetEndpoint {
    param(
        [string]$Name,
        [string]$Endpoint
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "DOWN"
    $httpCode = "-"
    $isOk = $false

    try {
        $resp = Invoke-WebRequest -Uri $Endpoint -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        $sw.Stop()
        $code = [int]$resp.StatusCode
        $httpCode = "$code"
        if ($code -ge 200 -and $code -lt 300) {
            $status = "OK"
            $isOk = $true
        }
    } catch {
        $sw.Stop()
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $httpCode = "$([int]$_.Exception.Response.StatusCode)"
        }
    }

    $latency = "$($sw.ElapsedMilliseconds)ms"
    Write-Output ("{0,-14} {1,-8} {2,-6} {3,-10} {4}" -f $Name, $status, $httpCode, $latency, $Endpoint)
    return $isOk
}

foreach ($svc in $services) {
    if (Test-FleetEndpoint -Name $svc.Name -Endpoint "$($svc.Url)/health") {
        $okCount++
    }
}

foreach ($contract in $contracts) {
    if (Test-FleetEndpoint -Name $contract.Name -Endpoint $contract.Endpoint) {
        $okCount++
    }
}

Write-Output ""
Write-Output "Fleet Health Summary: ${okCount}/${totalCount} OK"
if ($okCount -lt $totalCount) {
    exit 1
}
