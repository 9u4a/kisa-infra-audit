# W-10 (중) 마지막 사용자 이름 표시 안 함
# 판단 기준(가이드 원문): 양호 = "마지막 사용자 이름 표시 안 함"이 "사용"(=1) / 취약 = "사용 안 함"(=0/미설정)

$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$val = Test-RegistryValue -Path $path -Name "DontDisplayLastUserName"

if ($val -eq 1) {
    return New-CheckResult -Code "W-10" -Status "GOOD" -Detail "마지막 사용자 이름 표시 안 함 정책이 사용으로 설정됨" -Evidence "$path!DontDisplayLastUserName=$val"
} else {
    return New-CheckResult -Code "W-10" -Status "VULN" -Detail "마지막 사용자 이름 표시 안 함 정책이 설정되어 있지 않음" -Evidence "$path!DontDisplayLastUserName=$val"
}
