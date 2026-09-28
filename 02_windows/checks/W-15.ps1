# W-15 (상) 사용자 개인키 사용 시 암호 입력
# 판단 기준(가이드 원문): 양호 = 개인 키 사용 시마다 암호 입력을 받는 경우
# 레지스트리: HKLM\SOFTWARE\Policies\Microsoft\Cryptography\Protect!ForceKeyProtection = 2

$path = "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Protect"
$val = Test-RegistryValue -Path $path -Name "ForceKeyProtection"

if ($val -eq 2) {
    return New-CheckResult -Code "W-15" -Status "GOOD" -Detail "사용자 키 사용 시마다 암호 입력을 요구하도록 설정됨" -Evidence "$path!ForceKeyProtection=$val"
} else {
    return New-CheckResult -Code "W-15" -Status "VULN" -Detail "사용자 키 강력한 보호(매번 암호 입력) 정책이 설정되어 있지 않음" -Evidence "$path!ForceKeyProtection=$val"
}
