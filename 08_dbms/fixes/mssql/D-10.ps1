# D-10 (상) 원격에서 DB 서버로의 접속 제한 [MSSQL] — 조치 [fix: confirm]
# checks/mssql/D-10.ps1: 취약 = 모든 Windows 방화벽 프로필이 비활성화됨. 02_windows/fixes/
# W-64.ps1 과 완전히 동일한 방식(원격 데스크톱/원격 관리 사전정의 규칙을 먼저 활성화해 lockout
# 위험을 낮춘 뒤 방화벽 켜기)으로 조치한다. 구체적으로 어떤 IP만 DB 포트(1433)에 접근을
# 허용해야 하는지는 스크립트가 알 수 없어(U-28류 문제) 방화벽 활성화까지만 수행하고, IP 허용
# 범위는 가이드 안내대로 수동 구성해야 한다(MANUAL 로 남는 나머지 경우와 동일).

try {
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue
} catch { }

try {
    $before = Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "Get-NetFirewallProfile 실행 실패: $($_.Exception.Message)"
    $Global:FixEvidence = ""
    return
}

Backup-FixFirewallProfiles | Out-Null

try {
    Set-NetFirewallProfile -All -Enabled True -ErrorAction Stop
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "모든 방화벽 프로필을 사용으로 설정함(원격 데스크톱/원격 관리 규칙 그룹은 사전에 활성화). DB 포트(1433)에 특정 IP만 허용하는 세부 규칙은 별도로 수동 구성 필요"
    $Global:FixEvidence = "변경 전: " + (($before | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ", ")
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "Set-NetFirewallProfile 실패: $($_.Exception.Message)"
    $Global:FixEvidence = ""
}
