# PC-11 (상) 지원이 종료되지 않은 Windows OS Build 적용
# 판단 기준(가이드 원문): 양호 = 최신 빌드 적용 + 내부 관리 절차 수립·이행
#                        취약 = 미적용 또는 절차 미수립
# "최신/지원종료 여부"는 Microsoft 라이프사이클 페이지와 대조해야 하며 오프라인에서 자동 판정이
# 불가능하다 (빌드 EOL 일정은 수시로 바뀌므로 하드코딩하지 않는다). 현재 버전 정보를 근거로 제공한다.

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$displayVersion = Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DisplayVersion"
$evidence = "Caption=$($os.Caption) Version=$($os.Version) BuildNumber=$($os.BuildNumber) DisplayVersion=$displayVersion"

return New-CheckResult -Code "PC-11" -Status "MANUAL" `
    -Detail "지원 종료(EOL) 여부는 Microsoft Windows 수명 주기 페이지(learn.microsoft.com/lifecycle)와 대조해야 하고 관리 절차 수립 여부는 운영 정책 확인이 필요해 자동 판정할 수 없음. 현재 버전 정보를 근거로 수동 확인 필요" `
    -Evidence $evidence
