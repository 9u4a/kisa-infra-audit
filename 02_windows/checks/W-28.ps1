# W-28 (중) 터미널 서비스 암호화 수준 설정
# 판단 기준(가이드 원문): 양호 = RDP 미사용 또는 암호화 수준이 "클라이언트 호환 가능(중간)" 이상(>=2)
#                        취약 = 사용 중이며 "낮음"(1)으로 설정된 경우
# MinEncryptionLevel: 1=낮음 2=클라이언트 호환 가능 3=높음 4=FIPS 준수

$deny = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"
if ($deny -eq 1) {
    return New-CheckResult -Code "W-28" -Status "GOOD" -Detail "원격 데스크톱 서비스가 비활성화되어 있음" -Evidence "fDenyTSConnections=$deny"
}

$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
$level = Test-RegistryValue -Path $path -Name "MinEncryptionLevel"

if ($null -eq $level) {
    return New-CheckResult -Code "W-28" -Status "MANUAL" -Detail "MinEncryptionLevel 값을 조회하지 못함 — RDP 사용 여부 및 암호화 수준 수동 확인 필요"
}

if ([int]$level -ge 2) {
    return New-CheckResult -Code "W-28" -Status "GOOD" -Detail "터미널 서비스 암호화 수준이 ${level}(중간 이상)로 설정됨" -Evidence "$path!MinEncryptionLevel=$level"
} else {
    return New-CheckResult -Code "W-28" -Status "VULN" -Detail "터미널 서비스 암호화 수준이 ${level}(낮음)로 설정됨" -Evidence "$path!MinEncryptionLevel=$level"
}
