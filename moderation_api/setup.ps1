# ModChat Moderation API - one-time setup
# Run this once from inside the moderation_api folder:
#     powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# It creates the Python virtual environment and installs all dependencies.

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

Write-Host "=== ModChat Moderation API setup ===" -ForegroundColor Cyan

# 1. Check Python is available
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Write-Host "ERROR: Python is not installed or not on PATH." -ForegroundColor Red
    Write-Host "Install Python 3 from https://www.python.org/downloads/ (tick 'Add to PATH'), then re-run this script."
    exit 1
}
Write-Host ("Python found: " + (python --version)) -ForegroundColor Green

# 2. Create the virtual environment if it doesn't exist
if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    Write-Host "Creating virtual environment (.venv) ..."
    python -m venv .venv
} else {
    Write-Host ".venv already exists - reusing it."
}

# 3. Install dependencies
Write-Host "Upgrading pip ..."
.\.venv\Scripts\python.exe -m pip install --upgrade pip
Write-Host "Installing dependencies from requirements.txt (this downloads torch, ~250 MB - be patient) ..."
.\.venv\Scripts\python.exe -m pip install -r requirements.txt

# 4. Check the model files are present
$needed = @("config.json", "model.safetensors", "tokenizer.json", "tokenizer_config.json")
$missing = @()
foreach ($f in $needed) {
    if (-not (Test-Path (Join-Path ".\model" $f))) { $missing += $f }
}
Write-Host ""
if ($missing.Count -gt 0) {
    Write-Host "WARNING: model files missing from .\model :" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    Write-Host "Copy them from the Google Drive 'moderation_model' folder into .\model before running the server."
} else {
    Write-Host "All model files are present." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Cyan
Write-Host "Start the server with:   .\run.ps1"
