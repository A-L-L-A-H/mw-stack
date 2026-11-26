[CmdletBinding()]
param(
    [string]$HostAddress = "127.0.0.1",
    [int]$StartupTimeoutSec = 30
)

$ErrorActionPreference = "Stop"

$script:childProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$script:tempDirs = [System.Collections.Generic.List[string]]::new()

function Resolve-BunPath {
    $directBun = "C:\Users\bjo16\AppData\Roaming\npm\node_modules\bun\bin\bun.exe"
    if (Test-Path $directBun) {
        return $directBun
    }
    $bunCmd = (Get-Command bun -ErrorAction SilentlyContinue)
    if ($bunCmd) {
        if ($bunCmd.Source -match '\.exe$') {
            return $bunCmd.Source
        }
        $npmCandidate = Join-Path (Split-Path $bunCmd.Source) "node_modules\bun\bin\bun.exe"
        if (Test-Path $npmCandidate) {
            return $npmCandidate
        }
    }
    return "bun"
}

function Stop-AllChildProcesses {
    Write-Host "[cleanup] Terminating all child processes..." -ForegroundColor Yellow
    foreach ($proc in $script:childProcesses) {
        if ($proc -and -not $proc.HasExited) {
            try {
                Write-Host "[cleanup] Stopping PID $($proc.Id) ($($proc.ProcessName))..." -ForegroundColor Gray
                # Kill process tree cleanly on Windows
                cmd /c "taskkill /F /T /PID $($proc.Id) >nul 2>&1"
                $proc.WaitForExit(3000)
            } catch {
                Write-Warning "[cleanup] Failed to kill PID $($proc.Id): $_"
            }
        }
    }

    foreach ($dir in $script:tempDirs) {
        if (Test-Path $dir) {
            try {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                # Ignore temp dir cleanup errors
            }
        }
    }
}

function Wait-ForEndpoint {
    param(
        [string]$Name,
        [string]$Url,
        [int]$TimeoutSeconds = 20
    )
    Write-Host "[wait] Polling $Name at $Url (timeout: ${TimeoutSeconds}s)..." -NoNewline
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ([int]$resp.StatusCode -ge 200 -and [int]$resp.StatusCode -lt 300) {
                Write-Host " OK ($([int]$resp.StatusCode))" -ForegroundColor Green
                return $true
            }
        } catch {
            Start-Sleep -Milliseconds 400
        }
    }
    Write-Host " TIMEOUT" -ForegroundColor Red
    throw "Timed out waiting for $Name at $Url after ${TimeoutSeconds}s"
}

try {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   RockSoul Live E2E Smoke Test (All 4 Daemons + CLI)    " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    $rocksoulCliPath = "z:\repo\mw-rocksoul-cli\bin\rocksoul.exe"
    if (-not (Test-Path $rocksoulCliPath)) {
        throw "RockSoul CLI binary not found at $rocksoulCliPath"
    }

    # 1. Start mw-rocksoul-gateway (:4510)
    Write-Host "`n[1/4] Starting mw-rocksoul-gateway on port 4510..." -ForegroundColor Cyan
    $gwDir = "z:\repo\mw-rocksoul-gateway"
    $gwExe = Join-Path $gwDir "bin\mw-rocksoul-gateway.exe"
    $gwPsi = [System.Diagnostics.ProcessStartInfo]::new()
    if (Test-Path $gwExe) {
        $gwPsi.FileName = $gwExe
        $gwPsi.Arguments = "-port 4510 -auth-mode disabled"
    } else {
        $gwPsi.FileName = "go"
        $gwPsi.Arguments = "run ./cmd/mw-rocksoul-gateway -port 4510 -auth-mode disabled"
    }
    $gwPsi.WorkingDirectory = $gwDir
    $gwPsi.Environment["ROCKSOUL_AUTH_MODE"] = "disabled"
    $gwPsi.Environment["ROCKSOUL_GATEWAY_PORT"] = "4510"
    $gwPsi.UseShellExecute = $false
    $gwPsi.CreateNoWindow = $true
    $gwProc = [System.Diagnostics.Process]::Start($gwPsi)
    $script:childProcesses.Add($gwProc)
    Write-Host "  Started mw-rocksoul-gateway PID $($gwProc.Id)"

    # 2. Start mw-rocksoul-core (:4520)
    Write-Host "`n[2/4] Starting mw-rocksoul-core on port 4520..." -ForegroundColor Cyan
    $bunExe = Resolve-BunPath
    $coreDir = "z:\repo\mw-rocksoul-core"
    $corePsi = [System.Diagnostics.ProcessStartInfo]::new()
    $corePsi.FileName = $bunExe
    $corePsi.Arguments = "src/server.ts"
    $corePsi.WorkingDirectory = $coreDir
    $corePsi.Environment["ROCKSOUL_CORE_PORT"] = "4520"
    $corePsi.Environment["PORT"] = "4520"
    $corePsi.UseShellExecute = $false
    $corePsi.CreateNoWindow = $true
    $coreProc = [System.Diagnostics.Process]::Start($corePsi)
    $script:childProcesses.Add($coreProc)
    Write-Host "  Started mw-rocksoul-core PID $($coreProc.Id)"

    # 3. Start mw-rocksoul-mcp (:4530)
    Write-Host "`n[3/4] Starting mw-rocksoul-mcp on port 4530..." -ForegroundColor Cyan
    $mcpDir = "z:\repo\mw-rocksoul-mcp"
    $mcpPsi = [System.Diagnostics.ProcessStartInfo]::new()
    $mcpPsi.FileName = $bunExe
    $mcpPsi.Arguments = "src/server.ts"
    $mcpPsi.WorkingDirectory = $mcpDir
    $mcpPsi.Environment["ROCKSOUL_MCP_PORT"] = "4530"
    $mcpPsi.Environment["PORT"] = "4530"
    $mcpPsi.UseShellExecute = $false
    $mcpPsi.CreateNoWindow = $true
    $mcpProc = [System.Diagnostics.Process]::Start($mcpPsi)
    $script:childProcesses.Add($mcpProc)
    Write-Host "  Started mw-rocksoul-mcp PID $($mcpProc.Id)"

    # 4. Start mw-rocksoul-sandbox (:4540)
    Write-Host "`n[4/4] Starting mw-rocksoul-sandbox on port 4540..." -ForegroundColor Cyan
    $sbDir = "z:\repo\mw-rocksoul-sandbox"
    $sbPsi = [System.Diagnostics.ProcessStartInfo]::new()
    $sbPsi.FileName = $bunExe
    $sbPsi.Arguments = "src/server.ts"
    $sbPsi.WorkingDirectory = $sbDir
    $sbPsi.Environment["ROCKSOUL_SANDBOX_PORT"] = "4540"
    $sbPsi.Environment["PORT"] = "4540"
    # Ensure no auth token required for local verification
    $sbPsi.Environment["ROCKSOUL_SANDBOX_TOKEN"] = ""
    $sbPsi.UseShellExecute = $false
    $sbPsi.CreateNoWindow = $true
    $sbProc = [System.Diagnostics.Process]::Start($sbPsi)
    $script:childProcesses.Add($sbProc)
    Write-Host "  Started mw-rocksoul-sandbox PID $($sbProc.Id)"

    # 5. Wait for GET /health 200 on all 4 daemons
    Write-Host "`n--- Health Check Probes ---" -ForegroundColor Cyan
    Wait-ForEndpoint -Name "mw-rocksoul-gateway (:4510)" -Url "http://${HostAddress}:4510/health" -TimeoutSeconds $StartupTimeoutSec | Out-Null
    Wait-ForEndpoint -Name "mw-rocksoul-core (:4520)"    -Url "http://${HostAddress}:4520/health" -TimeoutSeconds $StartupTimeoutSec | Out-Null
    Wait-ForEndpoint -Name "mw-rocksoul-mcp (:4530)"     -Url "http://${HostAddress}:4530/health" -TimeoutSeconds $StartupTimeoutSec | Out-Null
    Wait-ForEndpoint -Name "mw-rocksoul-sandbox (:4540)" -Url "http://${HostAddress}:4540/health" -TimeoutSeconds $StartupTimeoutSec | Out-Null

    # 6. Run rocksoul doctor --json and verify all 4 Rocksoul daemons healthy
    Write-Host "`n--- Rocksoul CLI Doctor Probe ---" -ForegroundColor Cyan
    $doctorRaw = & $rocksoulCliPath doctor --json
    if ($LASTEXITCODE -ne 0) {
        throw "rocksoul doctor exited with code $LASTEXITCODE"
    }
    $doctorJson = $doctorRaw | ConvertFrom-Json
    Write-Host "Doctor probe report received ($($doctorJson.probes.Count) probes evaluated):"

    $targetDaemons = @("gateway", "core", "mcp", "sandbox")
    foreach ($daemon in $targetDaemons) {
        $probe = $doctorJson.probes | Where-Object { $_.name -eq $daemon }
        if (-not $probe) {
            throw "Doctor report missing probe for daemon '$daemon'"
        }
        if (-not $probe.healthy) {
            throw "Daemon '$daemon' probe reported UNHEALTHY: $($probe.error)"
        }
        Write-Host "  [+] $daemon : HEALTHY ($($probe.latencyMs)ms, url=$($probe.url))" -ForegroundColor Green
    }

    # 7. Run rocksoul init-tui --target opencode in temp directory
    Write-Host "`n--- Rocksoul CLI init-tui Verification ---" -ForegroundColor Cyan
    $tempInitDir = Join-Path ([System.IO.Path]::GetTempPath()) "rs-init-test-$([System.Guid]::NewGuid().ToString('n'))"
    [System.IO.Directory]::CreateDirectory($tempInitDir) | Out-Null
    $script:tempDirs.Add($tempInitDir)

    $initOutput = & $rocksoulCliPath init-tui --target opencode -dir $tempInitDir
    if ($LASTEXITCODE -ne 0) {
        $msg = "rocksoul init-tui failed with code $LASTEXITCODE - $initOutput"
        throw $msg
    }
    Write-Host "  init-tui executed successfully: $initOutput" -ForegroundColor Gray

    $opencodeConfigPath = Join-Path $tempInitDir "opencode.json"
    if (-not (Test-Path $opencodeConfigPath)) {
        throw "opencode.json was not generated at $opencodeConfigPath"
    }
    $opencodeContent = Get-Content -Path $opencodeConfigPath -Raw | ConvertFrom-Json
    if (-not $opencodeContent.'$schema' -or -not $opencodeContent.model) {
        throw "opencode.json missing expected fields ('`$schema', 'model')"
    }
    Write-Host "  [+] opencode.json generated and validated successfully (model: $($opencodeContent.model))" -ForegroundColor Green

    # 8. Test live HTTP endpoints
    Write-Host "`n--- Live Daemon HTTP Contracts Verification ---" -ForegroundColor Cyan

    # 8a. GET :4530/mcp/tools
    Write-Host "Testing GET http://${HostAddress}:4530/mcp/tools..." -NoNewline
    $toolsResp = Invoke-RestMethod -Uri "http://${HostAddress}:4530/mcp/tools" -Method Get -TimeoutSec 5
    if ($null -eq $toolsResp.tools -or $toolsResp.tools.Count -le 0) {
        throw "Expected tools array with elements from :4530/mcp/tools, got: $($toolsResp | ConvertTo-Json -Compress)"
    }
    Write-Host " OK ($($toolsResp.tools.Count) tools discovered)" -ForegroundColor Green

    # 8b. POST :4520/v1/risk/evaluate
    Write-Host "Testing POST http://${HostAddress}:4520/v1/risk/evaluate..." -NoNewline
    $riskPayload = @{
        principalId = "agent-e2e-smoke"
        action = "file:read"
        capability = "repo.read"
        dataClassification = "local_only"
        requestedTier = "R0"
        targetZone = "local"
        targetPaths = @("package.json")
    } | ConvertTo-Json -Depth 5
    $riskResp = Invoke-RestMethod -Uri "http://${HostAddress}:4520/v1/risk/evaluate" -Method Post -Body $riskPayload -ContentType "application/json" -TimeoutSec 5
    if ($riskResp.allowed -ne $true -or ($riskResp.effectiveRiskTier -ne "R0" -and $riskResp.assignedTier -ne "R0")) {
        throw "Unexpected risk evaluation response: $($riskResp | ConvertTo-Json -Compress)"
    }
    $tier = if ($riskResp.effectiveRiskTier) { $riskResp.effectiveRiskTier } else { $riskResp.assignedTier }
    Write-Host " OK (allowed=$($riskResp.allowed), tier=$tier)" -ForegroundColor Green

    # 8c. POST :4520/v1/evals/g0-g6
    Write-Host "Testing POST http://${HostAddress}:4520/v1/evals/g0-g6..." -NoNewline
    $evalPayload = "{}"
    $evalResp = Invoke-RestMethod -Uri "http://${HostAddress}:4520/v1/evals/g0-g6" -Method Post -Body $evalPayload -ContentType "application/json" -TimeoutSec 10
    if ($evalResp.passed -ne $true -or $null -eq $evalResp.gates) {
        throw "Unexpected G0-G6 eval harness response: $($evalResp | ConvertTo-Json -Compress)"
    }
    Write-Host " OK (passed=$($evalResp.passed), gates evaluated=$($evalResp.gates.PSObject.Properties.Count))" -ForegroundColor Green

    # 8d. POST :4540/leases -> DELETE :4540/leases/:id
    Write-Host "Testing POST http://${HostAddress}:4540/leases (lease acquisition)..." -NoNewline
    $leasePayload = @{
        ownerId = "agent-e2e-smoke"
        repoPath = "z:\repo\mw-stack"
        exclusive = $false
        ttlMs = 60000
        label = "e2e-smoke-test-lease"
    } | ConvertTo-Json
    $leaseResp = Invoke-RestMethod -Uri "http://${HostAddress}:4540/leases" -Method Post -Body $leasePayload -ContentType "application/json" -TimeoutSec 5
    if (-not $leaseResp.ok -or -not $leaseResp.lease.leaseId) {
        throw "Lease acquisition failed: $($leaseResp | ConvertTo-Json -Compress)"
    }
    $acquiredLeaseId = $leaseResp.lease.leaseId
    Write-Host " OK (leaseId=$acquiredLeaseId, fencingToken=$($leaseResp.lease.fencingToken))" -ForegroundColor Green

    Write-Host "Testing DELETE http://${HostAddress}:4540/leases/$acquiredLeaseId (lease release)..." -NoNewline
    $delResp = Invoke-RestMethod -Uri "http://${HostAddress}:4540/leases/$acquiredLeaseId" -Method Delete -TimeoutSec 5
    $relStatus = if ($delResp.status) { $delResp.status } elseif ($delResp.result) { $delResp.result.status } else { $null }
    if (-not $delResp.ok -or $relStatus -ne "released") {
        throw "Lease release failed: $($delResp | ConvertTo-Json -Compress)"
    }
    Write-Host " OK (status=$relStatus)" -ForegroundColor Green

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "   RockSoul Live E2E Smoke Test PASSED (100% End-to-End)  " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    exit 0

} catch {
    Write-Host "`n[FATAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    }
    exit 1
} finally {
    Stop-AllChildProcesses
}
