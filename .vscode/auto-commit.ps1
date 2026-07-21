param([string]$SavedFile = "")

# Auto-commit + push, triggered by the RunOnSave extension when a .sv file is saved.
# Failures are logged to .vscode/auto-commit.log rather than failing silently.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$log  = Join-Path $PSScriptRoot "auto-commit.log"
$lock = Join-Path $PSScriptRoot "auto-commit.lock"

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Add-Content -Path $log -Encoding utf8
}

# Rapid saves can overlap; a stale lock older than 2 minutes is ignored.
if (Test-Path $lock) {
    $age = (Get-Date) - (Get-Item $lock).LastWriteTime
    if ($age.TotalSeconds -lt 120) { exit 0 }
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType File -Path $lock -Force | Out-Null

try {
    Set-Location $repo
    git add -A

    # Nothing staged means nothing to do - no empty commits.
    git diff --cached --quiet
    if ($?) { exit 0 }

    $name = if ($SavedFile) { Split-Path -Leaf $SavedFile } else { "workspace" }
    git commit -m "Auto-commit: $name"
    if (-not $?) { Write-Log "commit failed"; exit 1 }

    # No 2>&1 here: git writes normal progress to stderr, and redirecting it
    # in PowerShell 5.1 turns that into a terminating error on success.
    git push
    if ($LASTEXITCODE -ne 0) {
        Write-Log "push failed for $name (exit $LASTEXITCODE)"
        exit 1
    }
    Write-Log "pushed $name"
}
catch {
    Write-Log "error: $($_.Exception.Message)"
}
finally {
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
