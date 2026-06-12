# Запуск Flutter с локальным Django (порт 8001).
# Без этого скрипта `flutter run` идёт на https://api.tojir.tj
# Эмулятор Android: -ApiHost 10.0.2.2
# Физический телефон: IP компьютера в Wi‑Fi (авто) или -ApiHost 192.168.x.x
param(
    [string]$ApiHost = "",
    [switch]$Prod
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if ($Prod) {
    Write-Host "Flutter -> PROD API (api.tojir.tj)"
    flutter run --dart-define=USE_PROD_API=true
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($ApiHost)) {
    $lan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notmatch '^127\.' -and
            $_.IPAddress -notmatch '^169\.254\.' -and
            $_.PrefixOrigin -ne 'WellKnown'
        } |
        Select-Object -First 1 -ExpandProperty IPAddress

    if ($lan) {
        Write-Host "Flutter -> http://${lan}:8001/api/v1 (физический телефон / LAN)"
        Write-Host "Убедитесь: python manage.py runserver 0.0.0.0:8001"
        flutter run --dart-define=API_HOST=$lan
    } else {
        Write-Host "Flutter -> http://10.0.2.2:8001/api/v1 (Android emulator)"
        flutter run --dart-define=API_HOST=10.0.2.2
    }
} else {
    Write-Host "Flutter -> http://${ApiHost}:8001/api/v1"
    flutter run --dart-define=API_HOST=$ApiHost
}
