# W-07 (중) Everyone 사용 권한을 익명 사용자에 적용
# 판단 기준(가이드 원문): 양호 = 정책이 "사용 안 함" / 취약 = "사용"
# 레지스트리: HKLM\SYSTEM\CurrentControlSet\Control\Lsa!EveryoneIncludesAnonymous (0=사용 안 함)

$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$val = Test-RegistryValue -Path $path -Name "EveryoneIncludesAnonymous"

if ($null -eq $val -or $val -eq 0) {
    return New-CheckResult -Code "W-07" -Status "GOOD" -Detail "Everyone 사용 권한을 익명 사용자에 적용 정책이 사용 안 함(또는 기본값)으로 설정됨" -Evidence "$path!EveryoneIncludesAnonymous=$val"
} else {
    return New-CheckResult -Code "W-07" -Status "VULN" -Detail "Everyone 사용 권한을 익명 사용자에 적용 정책이 사용으로 설정됨" -Evidence "$path!EveryoneIncludesAnonymous=$val"
}
