# W-01 (상) Administrator 계정 이름 변경 등 보안성 강화
# 판단 기준(가이드 원문): 양호 = Administrator 기본 계정 이름을 변경했거나 강화된 비밀번호를 적용
#                        취약 = 이름 미변경 및 단순 비밀번호
# 자동화 범위: 계정명 변경 여부만 판정(비밀번호 강도는 평문 확인 불가) — 이름이 기본값이면
#             비밀번호가 강력할 수도 있으므로 MANUAL 로 응답한다 (VULN 단정 금지).

# DC 에는 로컬 SAM 이 없어 아래 조회가 도메인 전체 계정 열거(LDAP 대량 조회)가 될 수 있다 - 건너뛴다.
if (Test-IsDomainController) {
    return New-CheckResult -Code "W-01" -Status "MANUAL" -Detail "도메인 컨트롤러: 빌트인 Administrator 는 도메인 계정이므로 AD(Active Directory 사용자 및 컴퓨터)에서 이름 변경 여부를 확인 필요(운영 부하 방지를 위해 계정 열거 생략)"
}
# F-W01(1.4.0): 관리자 이름을 바꾼 직후(=이 항목의 권고 조치)에는 Win32_UserAccount(WMI) 조회가 한동안 빈 결과로 끝나 ERROR 였다
# (양방향 케이스, CI run 41011236012/41041494009). SAM 을 직접 읽는 Get-LocalUser 를 먼저 쓰고, 모듈이 없는 OS(2012 R2)만 WMI.
$admin = $null
if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
    $lu = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -like 'S-1-5-*-500' } | Select-Object -First 1
    if ($lu) { $admin = [PSCustomObject]@{ Name = $lu.Name; SID = $lu.SID.Value } }
}
if (-not $admin) { $admin = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True and SID like 'S-1-5-%-500'" -ErrorAction SilentlyContinue }
if (-not $admin) {
    return New-CheckResult -Code "W-01" -Status "ERROR" -Detail "빌트인 Administrator 계정(RID 500)을 조회하지 못함"
}

if ($admin.Name -ne "Administrator") {
    return New-CheckResult -Code "W-01" -Status "GOOD" -Detail "빌트인 관리자 계정 이름이 '$($admin.Name)' 으로 변경되어 있음" -Evidence "Name=$($admin.Name) SID=$($admin.SID)"
} else {
    return New-CheckResult -Code "W-01" -Status "MANUAL" -Detail "빌트인 관리자 계정 이름이 기본값(Administrator)임 — 비밀번호 강도는 자동 확인 불가하므로 정책 및 실제 비밀번호를 수동 확인 필요" -Evidence "Name=$($admin.Name) SID=$($admin.SID)"
}
