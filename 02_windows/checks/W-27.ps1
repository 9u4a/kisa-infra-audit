# W-27 (상) 최신 Windows OS Build 버전 적용
# 판단 기준(가이드 원문): 양호 = 최신 Build 설치 + 적용 절차/방법이 수립된 경우
#                        취약 = 미설치 또는 절차 미수립
# "최신 여부"는 오프라인에서 MS 배포 최신본과 비교할 수 없고 "절차 수립 여부"는 운영 정책이므로
# 자동 판정이 불가능하다. 현재 빌드 정보를 근거로 MANUAL 로 제공한다.

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$evidence = "Caption=$($os.Caption) Version=$($os.Version) BuildNumber=$($os.BuildNumber) InstallDate=$($os.InstallDate)"

$hotfixCount = (Get-HotFix -ErrorAction SilentlyContinue | Measure-Object).Count
$evidence += "`n설치된 HotFix 수: $hotfixCount"

return New-CheckResult -Code "W-27" -Status "MANUAL" `
    -Detail "최신 Build 적용 여부 및 패치 절차 수립 여부는 Microsoft 배포 현황·운영 정책 확인이 필요해 자동 판정할 수 없음. 현재 빌드 정보를 근거로 최신 여부를 수동 확인 필요" `
    -Evidence $evidence
