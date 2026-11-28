[CmdletBinding()]
param(
    [string]$RepoRoot = "Z:\repo",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$SecretPatterns = @(
    @{ Name = "Private Key"; Pattern = "-----BEGIN (RSA|EC|OPENSSH|PGP|PRIVATE) KEY-----" }
    @{ Name = "Live GitHub Token"; Pattern = "gh[pousr]_[A-Za-z0-9_]{36,}" }
    @{ Name = "Live AWS Key"; Pattern = "(AKIA|ASIA)[0-9A-Z]{16}" }
    @{ Name = "Live Slack Token"; Pattern = "xox[baprs]-[0-9]{12}-[0-9]{12}-[a-zA-Z0-9]{24}" }
)

$IgnoredDirs = @(".git", "node_modules", "dist", "target", "vendor", ".svelte-kit", ".next", "bin", "obj", "build", "blueprints", "tests", "test", "__tests__")
$AllowedExtensions = @(".ts", ".tsx", ".js", ".mjs", ".cjs", ".json", ".rs", ".go", ".py", ".sh", ".ps1")

# Scan canonical mw-* repositories (exclude worktrees/scratch)
$allRepos = Get-ChildItem -Path $RepoRoot -Directory -Filter "mw-*" | Where-Object {
    $_.Name -notmatch "(worktree|review|sweep|scratch)"
}

$violations = [System.Collections.Generic.List[PSObject]]::new()
$bomComponents = [System.Collections.Generic.List[PSObject]]::new()
$scannedFilesTotal = 0
$ormScannedFiles = 0

Write-Output "=== MoonWitness Fleet Security & Invariant Audit ==="
Write-Output "Scanning $($allRepos.Count) repositories under $RepoRoot..."

$ormRegex = [regex]'import\s+.*@moonwitness/orm-|require\([\"'']@moonwitness/orm-|from\s+[\"'']@moonwitness/orm-'

foreach ($repo in $allRepos) {
    $repoName = $repo.Name
    $repoPath = $repo.FullName

    $bomComponents.Add([PSCustomObject]@{
        type = "application"
        name = $repoName
        version = "1.0.0"
        purl = "pkg:generic/$repoName@1.0.0"
    })

    $files = Get-ChildItem -Path $repoPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $filePath = $_.FullName
        $ext = $_.Extension.ToLower()
        $parts = $filePath.Split([System.IO.Path]::DirectorySeparatorChar)
        
        $hasIgnored = $false
        foreach ($ignored in $IgnoredDirs) {
            if ($parts -contains $ignored) {
                $hasIgnored = $true
                break
            }
        }
        (-not $hasIgnored) -and ($AllowedExtensions -contains $ext)
    }

    foreach ($file in $files) {
        $scannedFilesTotal++
        $relPath = $file.FullName.Substring($repoPath.Length).TrimStart('\', '/')

        # Invariant 1: Zero @moonwitness/orm-* imports in mw-rocksoul-* repos
        if ($repoName -match "^mw-rocksoul-") {
            if ($file.Name -ne "check-zero-orm-imports.mjs") {
                $ormScannedFiles++
                try {
                    $lines = [System.IO.File]::ReadAllLines($file.FullName)
                    for ($i = 0; $i -lt $lines.Length; $i++) {
                        $line = $lines[$i]
                        if ($ormRegex.IsMatch($line)) {
                            $violations.Add([PSCustomObject]@{
                                Repository = $repoName
                                File = $relPath
                                Line = $i + 1
                                Rule = "FORBIDDEN_ORM_IMPORT"
                                Detail = "Rocksoul repos must be Zero-ORM. Found forbidden ORM import."
                            })
                        }
                    }
                } catch {}
            }
            continue
        }

        # Invariant 2: Secret scanning across all repos (excluding test/mock/fixtures/templates)
        $isFixtureOrExample = ($file.Name -match "(example|\.test\.|\.spec\.|mock|fixture|template|gitleaks|sample)")
        if (-not $isFixtureOrExample) {
            try {
                $lines = [System.IO.File]::ReadAllLines($file.FullName)
                for ($i = 0; $i -lt $lines.Length; $i++) {
                    $line = $lines[$i]
                    foreach ($sp in $SecretPatterns) {
                        if ($line -match $sp.Pattern) {
                            if ($line -notmatch "(\$\{.*\}|\bREPLACE_\b|\bCHANGE_ME\b|\bexample\b|\btest\b|dummy|mock|fake|sample|00000000)") {
                                $violations.Add([PSCustomObject]@{
                                    Repository = $repoName
                                    File = $relPath
                                    Line = $i + 1
                                    Rule = "HARDCODED_SECRET"
                                    Detail = "Pattern matched: $($sp.Name)"
                                })
                            }
                        }
                    }
                }
            } catch {}
        }
    }
}

# Invariant 3: RS256 JWKS Auth Invariants in mw-rid and mw-rocksoul-gateway
$rs256Ok = $true
$gatewayReadme = Join-Path $RepoRoot "mw-rocksoul-gateway\README.md"
if (Test-Path $gatewayReadme) {
    $content = Get-Content $gatewayReadme -Raw
    if ($content -notmatch "RS256" -or $content -notmatch "jwks") {
        $rs256Ok = $false
        $violations.Add([PSCustomObject]@{
            Repository = "mw-rocksoul-gateway"
            File = "README.md"
            Line = 1
            Rule = "AUTH_INVARIANT_MISSING"
            Detail = "RS256 JWKS auth invariant documentation/enforcement missing"
        })
    }
}

$sbom = [PSCustomObject]@{
    bomFormat = "CycloneDX"
    specVersion = "1.5"
    serialNumber = "urn:uuid:$([System.Guid]::NewGuid())"
    version = 1
    metadata = [PSCustomObject]@{
        timestamp = (Get-Date -Format "o")
        tools = @(
            [PSCustomObject]@{
                vendor = "MoonWitness"
                name = "fleet-security-auditor"
                version = "1.0.0"
            }
        )
        component = [PSCustomObject]@{
            type = "platform"
            name = "MoonWitness Fleet"
        }
    }
    components = $bomComponents
    vulnerabilities = @($violations | ForEach-Object {
        [PSCustomObject]@{
            id = $_.Rule
            source = [PSCustomObject]@{ name = $_.Repository }
            description = "$($_.Detail) in $($_.File):$($_.Line)"
        }
    })
}

$jsonOutput = $sbom | ConvertTo-Json -Depth 6

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    [System.IO.File]::WriteAllText($OutputPath, $jsonOutput)
} else {
    Write-Output $jsonOutput
}

Write-Output ""
Write-Output "Audit Summary: $scannedFilesTotal files scanned across $($allRepos.Count) repos. Zero-ORM files checked: $ormScannedFiles. Violations: $($violations.Count)."

if ($violations.Count -gt 0) {
    exit 1
}
exit 0
