# audit.ps1 — 통합 런처 (PowerShell 5.1 호환, Windows 호스트용).
#
# 이 호스트에 적용되는 모든 카테고리를 한 번에 진단한다: 02_windows + 07_pc(항상) + 03_web(IIS
# 설치 여부 자동 감지, 미설치 시에도 안전하게 전 항목 해당없음으로 끝남) + 08_dbms(MSSQL 연결
# 시도, 실패 시 건너뜀). 각 카테고리의 개별 옵션(-Items/-Group 등)은 지원하지 않는다 - 특정
# 항목만 보려면 해당 카테고리의 run.ps1을 직접 실행할 것. 이 스크립트도 다른 run.*과 동일하게
# 대상 설정을 변경하지 않는다(진단 전용) - 조치는 카테고리별 fix.ps1을 참고.
#
# 사용법:
#   .\audit.ps1                               적용 가능한 모든 카테고리 진단 (로컬 Windows 통합 인증으로 MSSQL 시도)
#   .\audit.ps1 -SqlUser sa -SqlHost .        08_dbms 를 SQL 인증으로 시도 ($env:DB_PASSWORD 필요)
#   .\audit.ps1 -OutBase <dir>                 결과 출력 경로 지정 (기본: .\output)
param(
    [Alias("o")][string]$OutBase = "",
    [string]$SqlHost = "",
    [string]$SqlUser = "",
    [Alias("h")][switch]$Help
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Help) {
    Get-Content $MyInvocation.MyCommand.Path | Select-Object -Skip 1 -First 13 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

if (-not $OutBase) { $OutBase = Join-Path $ScriptDir "output" }
$HostName = $env:COMPUTERNAME
$Ts = Get-Date -Format "yyyyMMdd-HHmmss"
$RunLogDir = Join-Path $OutBase "$($HostName)_audit_$Ts"
New-Item -ItemType Directory -Force -Path $RunLogDir | Out-Null

Write-Host "=== 주요정보통신기반시설 통합 진단 ==="
Write-Host "호스트     : $HostName"
Write-Host "결과 경로  : $OutBase"
Write-Host "통합 로그  : $RunLogDir"
Write-Host "----------------------------------------------------------------------"

function Get-ResultDir($logPath) {
    $line = Select-String -Path $logPath -Pattern "결과 경로: " | Select-Object -First 1
    if ($line) { return ($line.Line -replace ".*결과 경로: ", "").Trim() }
    return ""
}

Write-Host "[1/4] 02_windows 진단 중..."
& powershell -NoProfile -File (Join-Path $ScriptDir "02_windows\run.ps1") -OutBase $OutBase *>&1 |
    Tee-Object -FilePath (Join-Path $RunLogDir "02_windows.log")
$WindowsDir = Get-ResultDir (Join-Path $RunLogDir "02_windows.log")

Write-Host "[2/4] 07_pc 진단 중..."
& powershell -NoProfile -File (Join-Path $ScriptDir "07_pc\run.ps1") -OutBase $OutBase *>&1 |
    Tee-Object -FilePath (Join-Path $RunLogDir "07_pc.log")
$PcDir = Get-ResultDir (Join-Path $RunLogDir "07_pc.log")

Write-Host "[3/4] 03_web(IIS) 진단 중... (IIS 미설치 시 전 항목 해당없음으로 끝남)"
& powershell -NoProfile -File (Join-Path $ScriptDir "03_web\run.ps1") -OutBase $OutBase *>&1 |
    Tee-Object -FilePath (Join-Path $RunLogDir "03_web.log")
$WebDir = Get-ResultDir (Join-Path $RunLogDir "03_web.log")

Write-Host "[4/4] 08_dbms(MSSQL) 진단 중... (연결 실패 시 각 항목이 개별적으로 오류로 보고됨)"
$dbmsArgs = @("-OutBase", $OutBase)
if ($SqlHost) { $dbmsArgs += @("-SqlHost", $SqlHost) }
if ($SqlUser) { $dbmsArgs += @("-SqlUser", $SqlUser) }
& powershell -NoProfile -File (Join-Path $ScriptDir "08_dbms\run.ps1") @dbmsArgs *>&1 |
    Tee-Object -FilePath (Join-Path $RunLogDir "08_dbms.log")
$DbmsDir = Get-ResultDir (Join-Path $RunLogDir "08_dbms.log")

Write-Host "----------------------------------------------------------------------"
Write-Host "=== 통합 진단 요약 ==="
foreach ($d in @($WindowsDir, $PcDir, $WebDir, $DbmsDir)) {
    if ($d -and (Test-Path (Join-Path $d "summary.txt"))) {
        Get-Content (Join-Path $d "summary.txt") | Write-Host
        Write-Host ""
    }
}
Write-Host "카테고리별 상세 결과 경로:"
if ($WindowsDir) { Write-Host "  02_windows : $WindowsDir" }
if ($PcDir) { Write-Host "  07_pc      : $PcDir" }
if ($WebDir) { Write-Host "  03_web     : $WebDir" }
if ($DbmsDir) { Write-Host "  08_dbms    : $DbmsDir" }
Write-Host "통합 로그: $RunLogDir"
