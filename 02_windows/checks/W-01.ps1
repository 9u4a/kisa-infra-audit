# W-01 (상) Administrator 계정 이름 변경 등 보안성 강화
# 판단 기준(가이드 원문): 양호 = Administrator 기본 계정 이름을 변경했거나 강화된 비밀번호를 적용
#                        취약 = 이름 미변경 및 단순 비밀번호
# 자동화 범위: 계정명 변경 여부만 판정(비밀번호 강도는 평문 확인 불가) — 이름이 기본값이면
#             비밀번호가 강력할 수도 있으므로 MANUAL 로 응답한다 (VULN 단정 금지).

$admin = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True and SID like 'S-1-5-%-500'" -ErrorAction SilentlyContinue
if (-not $admin) {
    return New-CheckResult -Code "W-01" -Status "ERROR" -Detail "빌트인 Administrator 계정(RID 500)을 조회하지 못함"
}

if ($admin.Name -ne "Administrator") {
    return New-CheckResult -Code "W-01" -Status "GOOD" -Detail "빌트인 관리자 계정 이름이 '$($admin.Name)' 으로 변경되어 있음" -Evidence "Name=$($admin.Name) SID=$($admin.SID)"
} else {
    return New-CheckResult -Code "W-01" -Status "MANUAL" -Detail "빌트인 관리자 계정 이름이 기본값(Administrator)임 — 비밀번호 강도는 자동 확인 불가하므로 정책 및 실제 비밀번호를 수동 확인 필요" -Evidence "Name=$($admin.Name) SID=$($admin.SID)"
}
