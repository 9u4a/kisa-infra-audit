# W-19 (상) 불필요한 IIS 서비스 구동 점검
# 판단 기준(가이드 원문): 양호 = IIS 미사용 또는 필요에 의해 사용 / 취약 = 불필요하게 사용
# "필요 여부"는 업무 판단이 필요하므로, 미설치 시에만 자동 GOOD, 구동 중이면 MANUAL.

$svc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
if (-not $svc) {
    return New-CheckResult -Code "W-19" -Status "GOOD" -Detail "IIS(World Wide Web Publishing Service)가 설치되어 있지 않음"
}

if ($svc.Status -ne "Running") {
    return New-CheckResult -Code "W-19" -Status "GOOD" -Detail "IIS 서비스가 설치되어 있으나 중지 상태임" -Evidence "W3SVC Status=$($svc.Status)"
} else {
    return New-CheckResult -Code "W-19" -Status "MANUAL" -Detail "IIS 서비스가 구동 중 — 실제 웹 서비스 제공 목적으로 필요한지 수동 확인 필요 (필요 시 03_web 카테고리로 별도 진단)" -Evidence "W3SVC Status=$($svc.Status)"
}
