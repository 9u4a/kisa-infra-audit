# WEB-18 (상) 웹 서비스 WebDAV 비활성화 [IIS]
# 판단 기준(가이드 원문): 양호 = WebDAV 비활성화 / 취약 = 활성화
# 자동화 범위: WebDAV 게시(Web-DAV-Publishing) Windows 기능 설치 여부와, 설치된 경우
# 사이트별 system.webServer/webdav/authoring@enabled 값을 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-18" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

# WebDAV 기능 설치 여부는 IIS 전역 모듈 목록(WebDAVModule)으로 확인한다. 예전의 Get-WindowsFeature /
# Get-WindowsOptionalFeature -Online(DISM)은 수십 초~수 분이 걸리고 Windows Update 등 서비싱 작업과
# 경합해 대기하거나 실패할 수 있었다(운영 안전 기준 S2). 조회 실패 시 $null → 사이트별 확인으로 진행.
$featureInstalled = $null
try {
    $mod = Get-WebConfiguration -Filter "system.webServer/globalModules/add[@name='WebDAVModule']" -PSPath "MACHINE/WEBROOT/APPHOST" -ErrorAction Stop
    $featureInstalled = [bool]$mod
} catch {
    $featureInstalled = $null
}

if ($featureInstalled -eq $false) {
    return New-CheckResult -Code "WEB-18" -Status "GOOD" -Detail "WebDAV 게시 기능이 설치되어 있지 않음"
}

$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-18" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $enabled = Get-IisConfigValue -Filter "system.webServer/webdav/authoring" -Name "enabled" -SiteName $site
    $evid += "[$site] webdav.authoring.enabled = $enabled"
    if ($enabled -eq $true) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-18" -Status "VULN" -Detail "WebDAV 이 활성화된 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-18" -Status "GOOD" -Detail "WebDAV 게시 기능은 설치되어 있으나 모든 사이트에서 비활성화됨" -Evidence ($evid -join "`n")
