# PC-16 (상) 화면보호기 대기 시간 설정 및 재시작 시 암호 보호 설정
# 판단 기준(가이드 원문): 양호 = 대기 시간 10분 이하 + 재시작 시 비밀번호 보호 설정
#                        취약 = 대기 시간 10분 초과 또는 비밀번호 보호 미설정
# 주의: HKCU(사용자별) 설정이라 이 스크립트를 실행하는 계정의 값만 확인 가능하다.

$path = "HKCU:\Control Panel\Desktop"
$active = Test-RegistryValue -Path $path -Name "ScreenSaveActive"
$secure = Test-RegistryValue -Path $path -Name "ScreenSaverIsSecure"
$timeout = Test-RegistryValue -Path $path -Name "ScreenSaveTimeOut"

$evidence = "(실행 계정 $env:USERNAME 기준) ScreenSaveActive=$active ScreenSaverIsSecure=$secure ScreenSaveTimeOut=$timeout"
$minutes = if ($timeout) { [int]$timeout / 60 } else { $null }

if ($active -eq "1" -and $secure -eq "1" -and $minutes -ne $null -and $minutes -le 10) {
    return New-CheckResult -Code "PC-16" -Status "GOOD" -Detail "화면보호기가 활성화되어 있고 대기시간 ${minutes}분 이하, 재시작 시 암호 보호로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "PC-16" -Status "MANUAL" -Detail "실행 계정 기준으로는 기준 미충족 — 화면보호기는 사용자별 설정이므로 실제 로그온 계정 기준으로 재확인 필요" -Evidence $evidence
}
