# PC-06 (상) 비인가 상용 메신저 사용 금지
# 판단 기준(가이드 원문): 양호 = Windows Messenger 중지 또는 상용 메신저 미설치
#                        취약 = Windows Messenger 실행 중이거나 상용 메신저 설치됨
# 자동화 범위: 레거시 Windows Messenger 서비스 + 대표 상용 메신저의 "설치" 흔적 + 실행 중 프로세스.
# W-R12: 가이드 기준은 "설치"인데 예전에는 실행 중 프로세스만 봐 꺼져 있는 설치본을 놓쳤다. 다음을 함께 본다.
#   - 프로그램 제거 목록(HKLM 64/32비트, 현재 로드된 사용자 하이브 HKU\<SID>)의 DisplayName
#   - 사용자별 설치 폴더(C:\Users\<사용자>\AppData\Local|Roaming\<제품>)
# 한계: 로그온하지 않은 사용자의 하이브는 열지 않는다(하이브 로드는 시스템 변경이라 S1 위반) - 폴더 흔적으로 보완.

$legacyRunning = $false
try { $svc = Get-ServiceChecked -Name "Messenger" }
catch { return New-CheckResult -Code "PC-06" -Status "ERROR" -Detail "Windows Messenger 서비스 상태를 조회하지 못함: $($_.Exception.Message)" }
if ($svc -and $svc.Status -eq "Running") { $legacyRunning = $true }

$commercialNames = @("KakaoTalk", "Skype", "SkypeApp", "LineWin", "NateOn", "Slack", "Discord", "WeChat", "Telegram")
# 제거 목록 DisplayName 패턴(한글 표시명 포함)
$namePattern = '(?i)KakaoTalk|카카오톡|Skype|^LINE$|LINE \(|NateOn|네이트온|Slack|Discord|WeChat|Telegram'
# 사용자별 설치 폴더(상대 경로)
$userDirs = @('AppData\Local\Kakao\KakaoTalk', 'AppData\Local\Discord', 'AppData\Local\slack', 'AppData\Roaming\Telegram Desktop',
    'AppData\Local\LINE', 'AppData\Roaming\Tencent\WeChat', 'AppData\Local\Microsoft\Skype for Desktop')

$foundProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $commercialNames -contains $_.ProcessName }

$installed = @()
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($k in @(Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' })) {
    $uninstallRoots += "Registry::HKEY_USERS\$($k.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Uninstall"
}
foreach ($root in $uninstallRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($e in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        $dn = "$($e.GetValue('DisplayName'))"
        if ($dn -and $dn -match $namePattern) { $installed += "$dn (제거 목록)" }
    }
}
$usersRoot = Join-Path $env:SystemDrive "Users"
foreach ($u in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) })) {
    foreach ($rel in $userDirs) {
        $p = Join-Path $u.FullName $rel
        if (Test-Path -LiteralPath $p) { $installed += "$p (설치 폴더)" }
    }
}
$installed = @($installed | Sort-Object -Unique)

$evidence = "Windows Messenger 서비스: $(if ($svc) { $svc.Status } else { '없음' })`n실행 중인 상용 메신저 프로세스: " +
    $(if ($foundProcs) { ($foundProcs.ProcessName | Sort-Object -Unique) -join ", " } else { "없음" }) +
    "`n설치 흔적: " + $(if ($installed.Count -gt 0) { "`n  " + ($installed -join "`n  ") } else { "없음" })

if (-not $legacyRunning -and -not $foundProcs -and $installed.Count -eq 0) {
    return New-CheckResult -Code "PC-06" -Status "GOOD" -Detail "Windows Messenger 미실행 및 상용 메신저 설치·실행 흔적이 발견되지 않음(로그온하지 않은 사용자의 레지스트리는 미확인)" -Evidence $evidence
} else {
    return New-CheckResult -Code "PC-06" -Status "VULN" -Detail "Windows Messenger 가 실행 중이거나 상용 메신저가 설치/실행되어 있음" -Evidence $evidence
}
