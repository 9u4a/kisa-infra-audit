# WEB-11 (중) 웹 서비스 경로 설정 [IIS]
# 판단 기준(가이드 원문): 양호 = 기타 업무와 분리된 경로로 설정 및 불필요 경로 없음
#                        취약 = 분리되지 않았거나 불필요 경로가 있는 경우
# 자동화 범위: 사이트 physicalPath 가 IIS 기본 설치 경로(%SystemDrive%\inetpub\wwwroot)
# 그대로인지 확인한다. 기본 경로 그대로면 OS/시스템 영역과 분리되지 않은 것으로 판단한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-11" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-11" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$defaultRoot = Join-Path $env:SystemDrive "inetpub\wwwroot"
$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $path = Get-IisSitePhysicalPath -SiteName $site
    $evid += "[$site] physicalPath = $path"
    if ($path -and ($path.TrimEnd('\') -ieq $defaultRoot.TrimEnd('\'))) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-11" -Status "VULN" -Detail "IIS 기본 설치 경로($defaultRoot)를 그대로 사용 중인 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-11" -Status "GOOD" -Detail "모든 사이트가 기본 설치 경로와 분리된 경로를 사용 중" -Evidence ($evid -join "`n")
