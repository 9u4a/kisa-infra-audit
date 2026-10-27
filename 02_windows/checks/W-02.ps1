# W-02 (상) Guest 계정 비활성화
# 판단 기준(가이드 원문): 양호 = Guest 계정 비활성화 / 취약 = 활성화

# DC 에는 로컬 SAM 이 없어 아래 조회가 도메인 전체 계정 열거(LDAP 대량 조회)가 될 수 있다 - 건너뛴다.
if (Test-IsDomainController) {
    return New-CheckResult -Code "W-02" -Status "MANUAL" -Detail "도메인 컨트롤러: Guest 는 도메인 계정이므로 AD 에서 비활성화 여부를 확인 필요(운영 부하 방지를 위해 계정 열거 생략)"
}
$guest = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True and SID like 'S-1-5-%-501'" -ErrorAction SilentlyContinue
if (-not $guest) {
    return New-CheckResult -Code "W-02" -Status "ERROR" -Detail "빌트인 Guest 계정(RID 501)을 조회하지 못함"
}

if ($guest.Disabled) {
    return New-CheckResult -Code "W-02" -Status "GOOD" -Detail "Guest 계정이 비활성화되어 있음" -Evidence "Name=$($guest.Name) Disabled=$($guest.Disabled)"
} else {
    return New-CheckResult -Code "W-02" -Status "VULN" -Detail "Guest 계정이 활성화되어 있음" -Evidence "Name=$($guest.Name) Disabled=$($guest.Disabled)"
}
