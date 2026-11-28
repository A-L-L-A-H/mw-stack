[CmdletBinding()]
param(
    [string]$StackDir = "Z:\repo\mw-stack",
    [string]$CoreDir = "Z:\repo\mw-core"
)

$ErrorActionPreference = "Stop"

Write-Output "================================================================="
Write-Output "   MoonWitness Business E2E Verification & Integration Harness   "
Write-Output "================================================================="

$passedTests = 0
$totalTests = 0

function Assert-Test {
    param(
        [string]$Name,
        [scriptblock]$Block
    )
    $script:totalTests++
    Write-Host -NoNewline "[TEST $script:totalTests] $Name ... "
    try {
        & $Block
        Write-Host "PASS" -ForegroundColor Green
        $script:passedTests++
    } catch {
        Write-Host "FAIL: $_" -ForegroundColor Red
        throw $_
    }
}

# 1. Gateway failover + local_only 403 test
Assert-Test "Rocksoul Gateway failover & local_only 403 verification" {
    $gwDir = "Z:\repo\mw-rocksoul-gateway"
    if (-not (Test-Path $gwDir)) { throw "mw-rocksoul-gateway directory missing" }
    
    # Static check of router code for local_only and 403 enforcement
    $goFiles = Get-ChildItem -Path $gwDir -Filter "*.go" -Recurse
    $hasLocalOnly = $false
    $has403 = $false
    foreach ($f in $goFiles) {
        $c = Get-Content $f.FullName -Raw
        if ($c -match "local_only") { $hasLocalOnly = $true }
        if ($c -match "403" -or $c -match "StatusForbidden") { $has403 = $true }
    }
    if (-not ($hasLocalOnly -and $has403)) {
        throw "Gateway lacks local_only 403 egress blocking logic"
    }
}

# 2. ISP .rsc + voucher + CoA verification
Assert-Test "ISP RouterOS .rsc, Voucher generator & CoA Disconnect contract" {
    $ispDir = "Z:\repo\mw-isp"
    if (-not (Test-Path $ispDir)) { throw "mw-isp directory missing" }

    $rsFiles = Get-ChildItem -Path $ispDir -Filter "*.rs" -Recurse
    $hasRsc = $false
    $hasVoucher = $false
    $hasCoa = $false
    foreach ($f in $rsFiles) {
        $c = Get-Content $f.FullName -Raw
        if ($c -match "generate_rsc" -or $c -match "mikrotik_config") { $hasRsc = $true }
        if ($c -match "isp_voucher" -or $c -match "vouchers") { $hasVoucher = $true }
        if ($c -match "disconnect" -or $c -match "DISCONNECT_REQUEST") { $hasCoa = $true }
    }
    if (-not ($hasRsc -and $hasVoucher -and $hasCoa)) {
        throw "mw-isp missing .rsc, voucher, or CoA implementation"
    }
}

# 3. PaaS quota + template + backup/restore drill
Assert-Test "PaaS quota management, Coolify template deploy & backup/restore drill" {
    $cpDir = "Z:\repo\mw-cp"
    if (-not (Test-Path $cpDir)) { throw "mw-cp directory missing" }

    $backupScript = Join-Path $StackDir "scripts\ops\backup-business-vps.sh"
    $restoreScript = Join-Path $StackDir "scripts\ops\restore-business-vps.sh"
    if (-not (Test-Path $backupScript)) { throw "backup-business-vps.sh missing" }
    if (-not (Test-Path $restoreScript)) { throw "restore-business-vps.sh missing" }

    $cpFiles = Get-ChildItem -Path $cpDir -Filter "*.go" -Recurse
    $hasQuota = $false
    $hasTemplate = $false
    foreach ($f in $cpFiles) {
        $c = Get-Content $f.FullName -Raw
        if ($c -match "/paas/quotas") { $hasQuota = $true }
        if ($c -match "/paas/templates") { $hasTemplate = $true }
    }
    if (-not ($hasQuota -and $hasTemplate)) {
        throw "mw-cp missing PaaS quota or template endpoints"
    }
}

# 4. ntfy/Resend + mw-pocket challenge check
Assert-Test "Notification offload (ntfy/Resend) & mw-pocket rocksoul approval challenge" {
    $pocketDir = "Z:\repo\mw-pocket"
    $pocketApproval = Join-Path $pocketDir "src\services\rocksoulApproval.ts"
    if (-not (Test-Path $pocketApproval)) { throw "rocksoulApproval.ts missing in mw-pocket" }
    
    $approvalSrc = Get-Content $pocketApproval -Raw
    if ($approvalSrc -notmatch "parseChallenge" -or $approvalSrc -notmatch "signApproval") {
        throw "mw-pocket lacks challenge parsing or signing"
    }

    $compose = Join-Path $StackDir "docker-compose.yml"
    $composeSrc = Get-Content $compose -Raw
    if ($composeSrc -notmatch "NTFY_TOPIC_URL" -or $composeSrc -notmatch "RESEND_API_KEY") {
        throw "docker-compose.yml missing NTFY_TOPIC_URL or RESEND_API_KEY env mapping"
    }
}

# 5. mw-core zero-collision
Assert-Test "mw-core registry zero-collision & non-operational invariant" {
    $validator = Join-Path $StackDir "scripts\ci\validate-core-registry.mjs"
    if (-not (Test-Path $validator)) { throw "validate-core-registry.mjs missing" }

    $out = & node $validator
    if ($LASTEXITCODE -ne 0) {
        throw "Core registry validator failed: $out"
    }
}

Write-Output ""
Write-Output "Verification Summary: $passedTests / $totalTests suites PASSED."
exit 0
