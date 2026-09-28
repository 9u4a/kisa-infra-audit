# PC-06 (상) 비인가 상용 메신저 사용 금지
# 판단 기준(가이드 원문): 양호 = Windows Messenger 중지 또는 상용 메신저 미설치
#                        취약 = Windows Messenger 실행 중이거나 상용 메신저 설치됨
# 자동화 범위: 레거시 Windows Messenger 서비스 + 대표 상용 메신저 프로세스 실행 여부로 판정.

$legacyRunning = $false
$svc = Get-Service -Name "Messenger" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") { $legacyRunning = $true }

$commercialNames = @("KakaoTalk", "Skype", "SkypeApp", "LineWin", "NateOn", "Slack", "Discord", "WeChat", "Telegram")
$foundProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $commercialNames -contains $_.ProcessName }

$evidence = "Windows Messenger 서비스: $(if ($svc) { $svc.Status } else { '없음' })`n실행 중인 상용 메신저 프로세스: " +
    $(if ($foundProcs) { ($foundProcs.ProcessName | Sort-Object -Unique) -join ", " } else { "없음" })

if (-not $legacyRunning -and -not $foundProcs) {
    return New-CheckResult -Code "PC-06" -Status "GOOD" -Detail "Windows Messenger 미실행 및 상용 메신저 프로세스가 발견되지 않음" -Evidence $evidence
} else {
    return New-CheckResult -Code "PC-06" -Status "VULN" -Detail "Windows Messenger 또는 상용 메신저가 실행 중임" -Evidence $evidence
}
