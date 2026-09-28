# W-02 (상) Guest 계정 비활성화
# 판단 기준(가이드 원문): 양호 = Guest 계정 비활성화 / 취약 = 활성화

$guest = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True and SID like 'S-1-5-%-501'" -ErrorAction SilentlyContinue
if (-not $guest) {
    return New-CheckResult -Code "W-02" -Status "ERROR" -Detail "빌트인 Guest 계정(RID 501)을 조회하지 못함"
}

if ($guest.Disabled) {
    return New-CheckResult -Code "W-02" -Status "GOOD" -Detail "Guest 계정이 비활성화되어 있음" -Evidence "Name=$($guest.Name) Disabled=$($guest.Disabled)"
} else {
    return New-CheckResult -Code "W-02" -Status "VULN" -Detail "Guest 계정이 활성화되어 있음" -Evidence "Name=$($guest.Name) Disabled=$($guest.Disabled)"
}
