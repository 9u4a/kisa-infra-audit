# WEB-25 (상) 주기적 보안 패치 및 벤더 권고사항 적용 [IIS]
# 판단 기준(가이드 원문): 양호 = 최신 패치 적용 + 패치 관리 정책 수립·운영
#                        취약 = 그렇지 않은 경우
# 자동화 범위: "최신 버전인지"와 "패치 정책을 수립·운영 중인지"는 이 도구가 판단할 수 없는
# 조직 정책 영역이라 항상 MANUAL 로 응답한다(01_unix U-64 등과 동일한 원칙). IIS/Windows 버전
# 정보만 증적으로 제공한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-25" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

$iisVersion = Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\InetStp" -Name "VersionString"
$os = try { (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption } catch { $null }
$evid = "InetStp VersionString = $iisVersion`nOS = $os"

return New-CheckResult -Code "WEB-25" -Status "MANUAL" -Detail "최신 보안 패치 적용 여부 및 패치 관리 정책 수립 여부는 수동 확인 필요" -Evidence $evid
