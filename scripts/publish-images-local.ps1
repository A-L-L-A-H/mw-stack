[CmdletBinding()]
param(
    [string]$Registry = "ghcr.io/a-l-l-a-h",
    [string]$Tag = "latest",
    [string[]]$Services = @(),
    [switch]$DryRun,
    [switch]$Push
)

$ErrorActionPreference = "Stop"

$AllServices = @(
    "mw-echo",
    "mw-rid",
    "mw-dock",
    "mw-xv",
    "mw-design",
    "mw-mylove",
    "mw-lab",
    "mw-mission",
    "mw-isp",
    "mw-cp",
    "mw-corpus",
    "mw-nexus",
    "mw-lore",
    "mw-studio",
    "mw-rocksoul-gateway",
    "mw-rocksoul-core",
    "mw-rocksoul-mcp",
    "mw-rocksoul-sandbox"
)

$TargetServices = if ($Services.Count -gt 0) { $Services } else { $AllServices }
$RepoRoot = "Z:\repo"

Write-Output "=== MoonWitness Zero-Card Local Docker Publisher ==="
Write-Output "Registry: $Registry"
Write-Output "Tag:      $Tag"
Write-Output "DryRun:   $DryRun"
Write-Output "Push:     $Push"
Write-Output "Services: $($TargetServices -join ', ')"
Write-Output ""

$buildSuccess = 0
$buildSkipped = 0

foreach ($svc in $TargetServices) {
    $svcDir = Join-Path $RepoRoot $svc
    $dockerfile = Join-Path $svcDir "Dockerfile"
    $imageName = "${Registry}/${svc}:${Tag}"

    if (-not (Test-Path $dockerfile)) {
        Write-Warning "[$svc] Skipping: No Dockerfile found at $dockerfile"
        $buildSkipped++
        continue
    }

    Write-Output "[$svc] Building $imageName from $svcDir..."
    if ($DryRun) {
        Write-Output "  [DRY-RUN] docker build -t $imageName $svcDir"
        if ($Push) {
            Write-Output "  [DRY-RUN] docker push $imageName"
        }
        $buildSuccess++
    } else {
        & docker build -t $imageName $svcDir
        if ($LASTEXITCODE -ne 0) {
            throw "Failed building $imageName"
        }
        if ($Push) {
            Write-Output "[$svc] Pushing $imageName..."
            & docker push $imageName
            if ($LASTEXITCODE -ne 0) {
                throw "Failed pushing $imageName"
            }
        }
        $buildSuccess++
    }
}

Write-Output ""
Write-Output "Publishing Summary: $buildSuccess built/verified, $buildSkipped skipped."
