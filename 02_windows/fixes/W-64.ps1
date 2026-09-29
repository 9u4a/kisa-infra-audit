# W-64 (중) 윈도우 방화벽 설정 [fix: confirm — deviation 있음]
# checks/W-64.ps1: 양호 = 모든 방화벽 프로필(도메인/개인/공용)이 사용으로 설정된 경우.
#
# 방화벽을 켜는 행위 자체가 이 스크립트가 실행 중인 원격 관리 세션(RDP/WinRM)을 차단할 수
# 있어(U-28과 같은 계열의 lockout 위험 — guide.json 의 deviation 필드 참고) 켜기 전에
# "원격 데스크톱"/"Windows 원격 관리" 사전정의 방화벽 규칙 그룹을 먼저 활성화한다. 그래도
# 위험이 완전히 없어지는 것은 아니므로(예: 비표준 포트로 WinRM 을 쓰는 경우) 반드시 confirm
# 단계에서 사람의 확인을 받는다.

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
    $Global:FixDetail = "모든 방화벽 프로필을 사용으로 설정함(원격 데스크톱/원격 관리 규칙 그룹은 사전에 활성화)"
    $Global:FixEvidence = "변경 전: " + (($before | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ", ")
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "Set-NetFirewallProfile 실패: $($_.Exception.Message)"
    $Global:FixEvidence = ""
}
