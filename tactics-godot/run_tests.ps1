# run_tests.ps1
# Scans for all *.test.gd files and runs them headlessly.
# Usage: powershell -File run_tests.ps1

$GODOT = "C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
$PROJECT = $PSScriptRoot

Write-Host "=== Hex Move Demo - Test Runner ===" -ForegroundColor Cyan

# Syntax-check all .gd files first
Write-Host "`n[1] Syntax check..." -ForegroundColor Yellow
$result = & $GODOT --headless --path $PROJECT --check-only --quit 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "SYNTAX ERRORS:" -ForegroundColor Red
    $result | Write-Host
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

# Runtime init check
Write-Host "`n[2] Runtime init (_ready)..." -ForegroundColor Yellow
$result = & $GODOT --headless --path $PROJECT --quit 2>&1
$errors = $result | Where-Object { $_ -match "ERROR|SCRIPT ERROR|Parse Error" }
if ($errors) {
    Write-Host "RUNTIME ERRORS:" -ForegroundColor Red
    $errors | Write-Host
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

# Run any .test.gd files found
$tests = Get-ChildItem -Path $PROJECT -Filter "*.test.gd" -Recurse
if ($tests.Count -eq 0) {
    Write-Host "`n[3] No .test.gd files found - skipping unit tests." -ForegroundColor DarkGray
} else {
    Write-Host "`n[3] Running $($tests.Count) test file(s)..." -ForegroundColor Yellow
    foreach ($test in $tests) {
        Write-Host "  -> $($test.Name)" -ForegroundColor Cyan
        $result = & $GODOT --headless --path $PROJECT --script $test.FullName --quit 2>&1
        $fail = $result | Where-Object { $_ -match "FAILED|ERROR|Assert" }
        if ($fail) {
            Write-Host "  FAILED:" -ForegroundColor Red
            $result | Write-Host
            exit 1
        } else {
            Write-Host "  PASSED" -ForegroundColor Green
        }
    }
}

Write-Host "`nAll checks passed." -ForegroundColor Green
