# W-12 (중) 익명 SID/이름 변환 허용 해제
# 판단 기준(가이드 원문): 양호 = "익명 SID/이름 변환 허용" 정책이 "사용 안 함" / 취약 = "사용"
# W-R1: 예전에는 RSOP WMI(그룹 정책 결과)만 보고 결과가 없으면 "미설정 = 기본값(사용 안 함)"으로 GOOD 이었다 -
# 로컬 보안 정책으로 켠 경우(RSOP 에 나타나지 않음)를 놓쳤다. secedit 내보내기의 [System Access]
# LSAAnonymousNameLookup(현재 적용 중인 LSA 정책 값, 0=사용 안 함 1=사용)으로 판정한다.

$val = Get-SecPolicyValue -Section "System Access" -Name "LSAAnonymousNameLookup"
if ($null -eq $val) {
    return New-CheckResult -Code "W-12" -Status "ERROR" -Detail "secedit 에서 LSAAnonymousNameLookup 값을 조회하지 못함"
}

if ("$val" -eq "0") {
    return New-CheckResult -Code "W-12" -Status "GOOD" -Detail "익명 SID/이름 변환 허용 정책이 사용 안 함으로 설정됨" -Evidence "secedit [System Access] LSAAnonymousNameLookup=$val"
} else {
    return New-CheckResult -Code "W-12" -Status "VULN" -Detail "익명 SID/이름 변환 허용 정책이 사용으로 설정됨" -Evidence "secedit [System Access] LSAAnonymousNameLookup=$val"
}
