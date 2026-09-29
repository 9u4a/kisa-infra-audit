# PC-15 (상) OS에서 제공하는 침입차단 기능 활성화 [fix: confirm — deviation 있음]
# 02_windows/fixes/W-64.ps1 과 동일한 이유(원격 관리 세션 lockout 위험)로 원격 데스크톱/
# 원격 관리 사전정의 규칙 그룹을 먼저 활성화한 뒤 방화벽을 켠다.

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
