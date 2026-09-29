# PC-06 (상) 비인가 상용 메신저 사용 금지 [fix: auto]
# checks/PC-06.ps1: 취약 = 레거시 Windows Messenger 서비스 구동 또는 상용 메신저 프로세스 실행 중.
# 설치 제거(가이드 원문 조치 방법)는 자동화 대상이 아니므로, 지금 실행 중인 프로세스를 종료하고
# Messenger 서비스를 비활성화하는 수준까지만 조치한다(재실행/재설치 방지는 아님 - 조직 정책
# 수립이 별도로 필요하다는 점을 detail 에 명시).

$commercialNames = @("KakaoTalk", "Skype", "SkypeApp", "LineWin", "NateOn", "Slack", "Discord", "WeChat", "Telegram")
$applied = @()

$svc = Get-Service -Name "Messenger" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Disable-FixService -Name "Messenger"
    if ($Global:FixStatus -eq "APPLIED") { $applied += "Windows Messenger 서비스" }
}

$foundProcs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $commercialNames -contains $_.ProcessName })
foreach ($p in $foundProcs) {
    try {
        Stop-Process -Id $p.Id -Force -ErrorAction Stop
        $applied += "$($p.ProcessName)(PID $($p.Id)) 종료"
    } catch { }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "실행 중이던 메신저 중지: $($applied -join ', ') — 재설치/재실행 방지를 위해 실제 프로그램 삭제 및 사용 금지 정책 수립은 별도로 필요"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "실행 중인 대상 메신저가 없음(이미 정상 상태였던 것으로 추정)"
}
$Global:FixEvidence = ""
