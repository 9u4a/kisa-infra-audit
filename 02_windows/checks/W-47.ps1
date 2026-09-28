# W-47 (하) 화면 보호기 설정
# 판단 기준(가이드 원문): 양호 = 화면 보호기 사용 + 대기시간 10분 이하 + 해제 시 암호 사용
#                        취약 = 미설정/암호 미사용/10분 초과
# 주의: 화면 보호기는 사용자별(HKCU) 설정이며, 이 스크립트를 실행하는 계정의 설정만 확인 가능하다.
# 실제 대화형 로그온 사용자와 다를 수 있으므로 참고용으로 활용한다.

$path = "HKCU:\Control Panel\Desktop"
$active = Test-RegistryValue -Path $path -Name "ScreenSaveActive"
$secure = Test-RegistryValue -Path $path -Name "ScreenSaverIsSecure"
$timeout = Test-RegistryValue -Path $path -Name "ScreenSaveTimeOut"

$evidence = "(실행 계정 $env:USERNAME 기준) ScreenSaveActive=$active ScreenSaverIsSecure=$secure ScreenSaveTimeOut=$timeout"
$minutes = if ($timeout) { [int]$timeout / 60 } else { $null }

if ($active -eq "1" -and $secure -eq "1" -and $minutes -ne $null -and $minutes -le 10) {
    return New-CheckResult -Code "W-47" -Status "GOOD" -Detail "화면 보호기가 활성화되어 있고 대기시간 ${minutes}분 이하, 암호 사용으로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-47" -Status "MANUAL" -Detail "실행 계정 기준으로는 기준 미충족 — 화면 보호기는 사용자별 설정이므로 실제 대화형 로그온 계정 기준으로 재확인 필요" -Evidence $evidence
}
