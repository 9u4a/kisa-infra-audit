# W-12 (중) 익명 SID/이름 변환 허용 해제
# 판단 기준(가이드 원문): 양호 = "익명 SID/이름 변환 허용" 정책이 "사용 안 함" / 취약 = "사용"
# 이 정책은 단순 레지스트리 값이 아닌 LSA 정책 객체라 secedit export 에도 나타나지 않는다.
# RSOP WMI(root\rsop\computer, RSOP_SecuritySettingBoolean, KeyName=LSAAnonymousNameLookup)로
# 조회하며, 결과가 없으면 "정책 미설정"으로 Windows 기본값(사용 안 함, 안전)이 적용된 것으로 본다.

try {
    $r = Get-CimInstance -Namespace "root\rsop\computer" -ClassName "RSOP_SecuritySettingBoolean" -ErrorAction Stop |
        Where-Object { $_.KeyName -eq "LSAAnonymousNameLookup" }
} catch {
    return New-CheckResult -Code "W-12" -Status "MANUAL" -Detail "RSOP WMI 조회 실패로 자동 판정 불가: $($_.Exception.Message)"
}

if (-not $r) {
    return New-CheckResult -Code "W-12" -Status "GOOD" -Detail "정책이 명시적으로 설정되어 있지 않음 (Windows 기본값인 '사용 안 함'이 적용됨)" -Evidence "RSOP LSAAnonymousNameLookup: 설정 없음(Not Defined)"
}

if ($r.Setting -eq $false) {
    return New-CheckResult -Code "W-12" -Status "GOOD" -Detail "익명 SID/이름 변환 허용 정책이 사용 안 함으로 설정됨" -Evidence "RSOP LSAAnonymousNameLookup=$($r.Setting)"
} else {
    return New-CheckResult -Code "W-12" -Status "VULN" -Detail "익명 SID/이름 변환 허용 정책이 사용으로 설정됨" -Evidence "RSOP LSAAnonymousNameLookup=$($r.Setting)"
}
