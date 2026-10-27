# W-03 (상) 불필요한 계정 제거
# 판단 기준(가이드 원문): 양호 = 불필요한 계정이 존재하지 않는 경우 / 취약 = 존재하는 경우
# "불필요" 여부는 조직 인사·운영 정보가 필요해 자동 판정이 불가능하다 (Unix U-07과 동일 성격).
# 자동화 범위: 활성화된 로컬 계정 목록과 마지막 로그온 시각을 근거로 제시, 최종 판단은 MANUAL.

# DC 에서는 이 조회가 도메인 전체 계정 열거가 되어 DC 부하와 거대한 증적이 생길 수 있다 - 건너뛴다.
if (Test-IsDomainController) {
    return New-CheckResult -Code "W-03" -Status "MANUAL" -Detail "도메인 컨트롤러: 계정은 도메인(AD) 기준으로 별도 점검 필요(운영 부하 방지를 위해 계정 열거 생략)"
}
$accounts = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Disabled } |
    Select-Object Name, SID, PasswordExpires, PasswordRequired

$evidence = ($accounts | ForEach-Object { "$($_.Name) (SID=$($_.SID))" }) -join "`n"

return New-CheckResult -Code "W-03" -Status "MANUAL" `
    -Detail "계정의 '불필요' 여부는 조직 운영 정보(퇴직/휴직 등)가 필요해 자동 판정할 수 없음. 아래 활성 계정 목록을 근거로 수동 검토 필요" `
    -Evidence "[활성화된 로컬 계정]`n$evidence"
