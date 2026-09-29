# WEB-10 (상) 불필요한 프록시 설정 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = 불필요한 Proxy 설정을 제한한 경우 / 취약 = 제한하지 않은 경우
# 자동화 범위: IIS 자체에는 프록시 기능이 기본 내장되어 있지 않고, Application Request Routing
# (ARR) 모듈을 별도 설치해야 system.webServer/proxy 섹션이 생긴다. 이 섹션이 없으면 프록시
# 기능 자체가 없는 것이므로 양호, 있으면 enabled 값을 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-10" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

try {
    $section = Get-WebConfiguration -Filter "system.webServer/proxy" -PSPath "MACHINE/WEBROOT/APPHOST" -ErrorAction Stop
} catch {
    $section = $null
}

if (-not $section) {
    return New-CheckResult -Code "WEB-10" -Status "GOOD" -Detail "ARR(Application Request Routing) 프록시 모듈이 설치되어 있지 않음(프록시 기능 없음)"
}

$enabled = $section.enabled
if ($enabled -eq $true) {
    return New-CheckResult -Code "WEB-10" -Status "VULN" -Detail "ARR 프록시 기능(system.webServer/proxy@enabled)이 활성화되어 있음" -Evidence "enabled = $enabled"
}
return New-CheckResult -Code "WEB-10" -Status "GOOD" -Detail "ARR 모듈은 설치되어 있으나 프록시 기능은 비활성화됨" -Evidence "enabled = $enabled"
