<#
.SYNOPSIS
    Idempotent PowerShell script to audit and clean non-git orphan work directories in z:\repo

.DESCRIPTION
    Scans for known orphan directories (mw-control, mw-xv-review-7e964, mw-xv-sweep),
    verifies they are not git repositories, and safely archives or prunes them.
    Runs in -DryRun mode by default listing candidates with disk usage.
    Produces disk savings report on actual run.

.PARAMETER DryRun
    Default. Lists orphan candidates and estimated disk savings without making changes.

.PARAMETER Apply
    Performs actual archive/prune of verified non-git orphan folders.

.PARAMETER ArchiveRoot
    Root directory for archived folders (default: z:\repo\_archive).

.EXAMPLE
    powershell -File cleanup-orphan-workdirs.ps1 -DryRun

.EXAMPLE
    powershell -File cleanup-orphan-workdirs.ps1 -Apply -ArchiveRoot z:\repo\_archive
#>

[CmdletBinding()]
param(
    [switch]$DryRun = $true,
    [switch]$Apply,
    [string]$ArchiveRoot = "z:\repo\_archive",
    [int]$MinAgeDays = 7
)

# Known orphan patterns to scan
$OrphanPatterns = @(
    "mw-control",
    "mw-xv-review-7e964",
    "mw-xv-sweep"
)

$RepoRoot = "z:\repo"
$TotalSavingsBytes = 0
$Candidates = @()

Write-Host "=== Orphan Workdir Cleanup Audit ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'DRY-RUN (default)' })" -ForegroundColor Yellow
Write-Host "Repo Root: $RepoRoot"
Write-Host "Archive Root: $ArchiveRoot"
Write-Host "Min Age: $MinAgeDays days"
Write-Host ""

foreach ($pattern in $OrphanPatterns) {
    $fullPath = Join-Path $RepoRoot $pattern
    
    if (-not (Test-Path $fullPath)) {
        Write-Host "[SKIP] $pattern - does not exist" -ForegroundColor Gray
        continue
    }

    # Verify it's NOT a git repository
    $gitDir = Join-Path $fullPath ".git"
    if (Test-Path $gitDir -PathType Container) {
        Write-Host "[SKIP] $pattern - is a git repository (has .git)" -ForegroundColor Yellow
        continue
    }

    # Check if it's a git worktree
    $gitWorktreeCheck = git -C $RepoRoot worktree list --porcelain 2>$null | Select-String -Pattern "worktree $fullPath"
    if ($gitWorktreeCheck) {
        Write-Host "[SKIP] $pattern - is a git worktree" -ForegroundColor Yellow
        continue
    }

    # Calculate directory size
    $sizeBytes = (Get-ChildItem -Path $fullPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
    $sizeGB = [math]::Round($sizeBytes / 1GB, 3)

    # Check age
    $dirInfo = Get-Item $fullPath
    $ageDays = (Get-Date) - $dirInfo.LastWriteTime | Select-Object -ExpandProperty Days

    if ($ageDays -lt $MinAgeDays) {
        Write-Host "[SKIP] $pattern - age ${ageDays}d < ${MinAgeDays}d minimum" -ForegroundColor Yellow
        continue
    }

    $candidate = [pscustomobject]@{
        Name      = $pattern
        Path      = $fullPath
        SizeBytes = $sizeBytes
        SizeMB    = $sizeMB
        SizeGB    = $sizeGB
        AgeDays   = $ageDays
    }
    $Candidates += $candidate
    $TotalSavingsBytes += $sizeBytes

    Write-Host "[CANDIDATE] $pattern" -ForegroundColor Green
    Write-Host "  Path: $fullPath"
    Write-Host "  Size: $sizeMB MB ($sizeGB GB)"
    Write-Host "  Age:  $ageDays days"
    Write-Host ""
}

if ($Candidates.Count -eq 0) {
    Write-Host "No eligible orphan directories found." -ForegroundColor Cyan
    exit 0
}

$TotalSavingsMB = [math]::Round($TotalSavingsBytes / 1MB, 2)
$TotalSavingsGB = [math]::Round($TotalSavingsBytes / 1GB, 3)

Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Candidates: $($Candidates.Count)"
Write-Host "Total Estimated Savings: $TotalSavingsMB MB ($TotalSavingsGB GB)"
Write-Host ""

if ($DryRun -and -not $Apply) {
    Write-Host "DRY-RUN complete. Re-run with -Apply to execute cleanup." -ForegroundColor Yellow
    exit 0
}

if ($Apply) {
    # Ensure archive root exists
    if (-not (Test-Path $ArchiveRoot)) {
        New-Item -Path $ArchiveRoot -ItemType Directory -Force | Out-Null
        Write-Host "Created archive root: $ArchiveRoot" -ForegroundColor Cyan
    }

    $Archived = @()
    $Errors = @()

    foreach ($c in $Candidates) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $archiveName = "$($c.Name)_$timestamp"
        $archivePath = Join-Path $ArchiveRoot $archiveName

        try {
            Write-Host "Archiving $($c.Name) -> $archivePath" -ForegroundColor Cyan
            Move-Item -Path $c.Path -Destination $archivePath -Force -ErrorAction Stop
            $Archived += [pscustomobject]@{
                Name       = $c.Name
                ArchivePath = $archivePath
                SizeMB     = $c.SizeMB
                SizeGB     = $c.SizeGB
            }
            Write-Host "  [OK] Archived $($c.SizeMB) MB" -ForegroundColor Green
        }
        catch {
            $Errors += [pscustomobject]@{
                Name  = $c.Name
                Error = $_.Exception.Message
            }
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "=== CLEANUP COMPLETE ===" -ForegroundColor Cyan
    Write-Host "Archived: $($Archived.Count) directories"
    Write-Host "Errors:   $($Errors.Count)"
    
    if ($Archived.Count -gt 0) {
        $ActualSavingsMB = [math]::Round(($Archived | Measure-Object -Property SizeMB -Sum).Sum, 2)
        $ActualSavingsGB = [math]::Round(($Archived | Measure-Object -Property SizeGB -Sum).Sum, 3)
        Write-Host "Actual Disk Freed: $ActualSavingsMB MB ($ActualSavingsGB GB)"
        Write-Host ""
        Write-Host "Archived Items:" -ForegroundColor Cyan
        $Archived | Format-Table Name, ArchivePath, SizeMB, SizeGB -AutoSize | Out-Host
    }

    if ($Errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Errors:" -ForegroundColor Red
        $Errors | Format-Table Name, Error -AutoSize | Out-Host
        exit 1
    }
}