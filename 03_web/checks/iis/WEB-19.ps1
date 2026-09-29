# WEB-19 (중) 웹 서비스 SSI(Server Side Includes) 사용 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = SSI 사용 설정이 비활성화된 경우 / 취약 = 활성화된 경우
# 자동화 범위: SSI 는 IIS 에서 .stm/.shtm/.shtml 확장자가 ssinc.dll(SSI 모듈) 핸들러에 매핑되어
# 있을 때 동작한다. 사이트별 handler mapping 에서 해당 매핑이 존재·활성 상태인지 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-19" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-19" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$ssiExt = @(".stm", ".shtm", ".shtml")

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    try {
        $handlers = Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath "IIS:\Sites\$site" -ErrorAction Stop
    } catch {
        $handlers = @()
    }
    $hit = @($handlers | Where-Object { $h = $_; $ssiExt | Where-Object { $h.path -ilike "*$_" } })
    $evid += "[$site] SSI 확장자 매핑: $(if ($hit.Count -gt 0) { ($hit | ForEach-Object { $_.name }) -join ', ' } else { '없음' })"
    if ($hit.Count -gt 0) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-19" -Status "VULN" -Detail "SSI(.stm/.shtm/.shtml) 핸들러 매핑이 활성화된 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-19" -Status "GOOD" -Detail "모든 사이트에서 SSI 핸들러 매핑이 없음" -Evidence ($evid -join "`n")
