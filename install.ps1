#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet("exe", "docker")]
    [string]$Mode = "exe",

    [ValidateSet("lite", "ops", "saas", "isp", "epistemic", "tunnel", "proxy", "full")]
    [string]$Profile = "lite",

    [string]$InstallDir = "$env:LOCALAPPDATA\MoonWitness",

    [string]$RepoUrl = "https://github.com/A-L-L-A-H/mw-stack.git",

    [switch]$NoStart
)

$ErrorActionPreference = "Stop"

function New-RandomHexSecret {
    param([int]$ByteLength = 24)
    $bytes = New-Object byte[] $ByteLength
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return ([System.BitConverter]::ToString($bytes) -replace "-", "").ToLowerInvariant()
}

function Install-EchoExecutable {
    param([string]$TargetDir, [bool]$SkipStart)

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    $exePath = Join-Path $TargetDir "mw-echo.exe"
    $downloadUrl = "https://github.com/A-L-L-A-H/mw-echo/releases/latest/download/mw-echo-windows-amd64.exe"

    Write-Host "[mw-stack] Downloading mw-echo.exe from $downloadUrl..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -UseBasicParsing

    if (-not (Test-Path $exePath)) {
        throw "Failed to download mw-echo.exe to $exePath"
    }

    Write-Host "[mw-stack] Installed mw-echo.exe at $exePath"
    if (-not $SkipStart) {
        Write-Host "[mw-stack] Starting mw-echo.exe..."
        Start-Process -FilePath $exePath -WorkingDirectory $TargetDir
    }
}

function Install-DockerFleet {
    param([string]$TargetDir, [string]$FleetProfile, [string]$GitRepoUrl, [bool]$SkipStart)

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker Desktop / Docker Engine is required for -Mode docker. Install Docker and retry."
    }

    docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose v2 is required for -Mode docker."
    }

    $stackDir = Join-Path $TargetDir "mw-stack"
    if (Test-Path (Join-Path $stackDir ".git")) {
        Write-Host "[mw-stack] Updating $stackDir..."
        git -C $stackDir pull --ff-only origin main
    } else {
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
        Write-Host "[mw-stack] Cloning $GitRepoUrl into $stackDir..."
        git clone --depth 1 $GitRepoUrl $stackDir
    }

    $envFile = Join-Path $stackDir ".env"
    if (-not (Test-Path $envFile)) {
        Write-Host "[mw-stack] Generating cryptographic secrets in $envFile..."
        $template = Get-Content -Raw -Path (Join-Path $stackDir ".env.example")
        $template = $template -replace "(?m)^MW_PROFILE=.*$", "MW_PROFILE=$FleetProfile"
        $template = $template -replace "(?m)^MW_API_SECRET=.*$", ("MW_API_SECRET=" + (New-RandomHexSecret))
        $template = $template -replace "(?m)^MW_JWT_SECRET=.*$", ("MW_JWT_SECRET=" + (New-RandomHexSecret))
        $template = $template -replace "(?m)^MW_ENCRYPTION_KEY=.*$", ("MW_ENCRYPTION_KEY=" + (New-RandomHexSecret))
        $template = $template -replace "(?m)^POSTGRES_PASSWORD=.*$", ("POSTGRES_PASSWORD=" + (New-RandomHexSecret))
        Set-Content -Path $envFile -Value $template -Encoding UTF8
    }

    if (-not $SkipStart) {
        $composeFile = Join-Path $stackDir "docker-compose.yml"
        Write-Host "[mw-stack] Pulling GHCR images for profile '$FleetProfile'..."
        docker compose -f $composeFile --env-file $envFile --profile $FleetProfile pull
        Write-Host "[mw-stack] Starting MoonWitness fleet (profile: $FleetProfile)..."
        docker compose -f $composeFile --env-file $envFile --profile $FleetProfile up -d --remove-orphans
    }

    Write-Host "[mw-stack] Docker fleet ready in $stackDir (profile: $FleetProfile)."
}

if ($Mode -eq "exe") {
    Install-EchoExecutable -TargetDir $InstallDir -SkipStart $NoStart.IsPresent
} else {
    Install-DockerFleet -TargetDir $InstallDir -FleetProfile $Profile -GitRepoUrl $RepoUrl -SkipStart $NoStart.IsPresent
}
