# WEB-19 (중) 웹 서비스 SSI(Server Side Includes) 사용 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = SSI 사용 설정이 비활성화된 경우 / 취약 = 활성화된 경우
# 자동화 범위: SSI 는 IIS 에서 .stm/.shtm/.shtml 확장자가 ssinc.dll(SSI 모듈) 핸들러에 매핑되어
# 있을 때 동작한다. 사이트별 handler mapping 에서 해당 매핑이 존재·활성 상태인지 확인한다.
# 1.5.0 A24: 하위 application·virtual directory 가 자기 web.config 로 SSI 핸들러를 다시 추가할 수 있어(예전에는 사이트
# 루트만 봄) Get-IisSiteConfigPaths 로 열거한 경로마다 유효 handler 목록을 확인한다.

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
    foreach ($cp in (Get-IisSiteConfigPaths -SiteName $site)) {
        try {
            $handlers = Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath $cp.PSPath -ErrorAction Stop
        } catch {
            # WEB-R7: 조회 실패를 "매핑 없음 = GOOD" 으로 넘기지 않는다 - 실패 표시(run.ps1 이 GOOD 을 ERROR 로 바꿈)
            $Global:IisConfigQueryFailed = $true
            $Global:IisConfigQueryError = "handlers ($($cp.Label)): $($_.Exception.Message)"
            $evid += "[$($cp.Label)] handler mapping 조회 실패: $($_.Exception.Message)"
            continue
        }
        $hit = @($handlers | Where-Object { $h = $_; $ssiExt | Where-Object { $h.path -ilike "*$_" } })
        $evid += "[$($cp.Label)] SSI 확장자 매핑: $(if ($hit.Count -gt 0) { ($hit | ForEach-Object { $_.name }) -join ', ' } else { '없음' })"
        if ($hit.Count -gt 0) { $vuln += $cp.Label }
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-19" -Status "VULN" -Detail "SSI(.stm/.shtm/.shtml) 핸들러 매핑이 활성화된 사이트/경로: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-19" -Status "GOOD" -Detail "모든 사이트(하위 application/virtual directory 포함)에서 SSI 핸들러 매핑이 없음" -Evidence ($evid -join "`n")
