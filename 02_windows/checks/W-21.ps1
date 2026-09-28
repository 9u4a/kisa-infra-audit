# W-21 (상) 암호화되지 않는 FTP 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = FTP 미사용 또는 Secure FTP 사용 / 취약 = 평문 FTP 사용

$svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
if (-not $svc) {
    return New-CheckResult -Code "W-21" -Status "GOOD" -Detail "FTP 서비스(Microsoft FTP Service)가 설치되어 있지 않음"
}

if ($svc.Status -eq "Running") {
    return New-CheckResult -Code "W-21" -Status "VULN" -Detail "암호화되지 않은 FTP 서비스가 구동 중임" -Evidence "FTPSVC Status=$($svc.Status)"
} else {
    return New-CheckResult -Code "W-21" -Status "GOOD" -Detail "FTP 서비스가 설치되어 있으나 중지 상태임" -Evidence "FTPSVC Status=$($svc.Status)"
}
