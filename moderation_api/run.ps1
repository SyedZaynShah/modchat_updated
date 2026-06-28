# ModChat Moderation API - start the server
# Run from inside the moderation_api folder:
#     powershell -ExecutionPolicy Bypass -File .\run.ps1
#
# Run setup.ps1 first if you haven't already.

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    Write-Host "ERROR: .venv not found. Run setup first:  .\setup.ps1" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path ".\model\model.safetensors")) {
    Write-Host "ERROR: model files missing from .\model" -ForegroundColor Red
    Write-Host "Copy config.json, model.safetensors, tokenizer.json and tokenizer_config.json"
    Write-Host "from the Google Drive 'moderation_model' folder into .\model, then re-run."
    exit 1
}

# Label order discovered from the trained model: index 0=normal, 1=abusive, 2=swear, 3=threat
$env:LABELS = "normal,abusive,swear,threat"

Write-Host "Starting moderation API on http://127.0.0.1:8000  (Ctrl+C to stop)" -ForegroundColor Cyan
.\.venv\Scripts\python.exe -m uvicorn app:app --host 0.0.0.0 --port 8000
