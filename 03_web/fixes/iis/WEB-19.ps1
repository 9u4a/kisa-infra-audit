# WEB-19 (중) 웹 서비스 SSI(Server Side Includes) 사용 제한 [IIS] — 조치 [fix: confirm]
# 변경: IIS 사이트·하위 application/virtual directory 별 system.webServer/handlers 에서 .stm/.shtm/.shtml 핸들러 매핑 제거(원복 불가)
# 원복: 불가 — 제거한 SSI 핸들러 매핑은 자동으로 다시 등록하지 않음
# checks/iis/WEB-19.ps1 이 찾아낸 .stm/.shtm/.shtml 핸들러 매핑을 제거한다. 컬렉션 원소
# 제거라 표준 webconfig 백업/원복 대상이 아니다(WEB-13과 동일한 한계).

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음"; $Global:FixEvidence = ""
    return
}

$ssiExt = @(".stm", ".shtm", ".shtml")
$applied = @()
$failed = @()

# 원복 경로가 없는 자원 - 원복 시 "원복 불가"로 정직하게 보고되도록 변경 직전에 표시(lib/Common.psm1)
Register-FixNoRollback -Reason "IIS 에서 제거한 SSI 핸들러 매핑 - 필요 시 처리기 매핑에서 수동 재등록"
# V-R1: 진단(checks/iis/WEB-19.ps1)과 같이 사이트 루트뿐 아니라 하위 application·virtual directory 가 다시 추가한 매핑도 지운다
# (Get-IisSiteConfigPaths, 루트 먼저 - 루트에서 지운 상속 매핑은 하위에서 다시 읽을 때 없다). 예전에는 사이트 루트만 지워 재검증 실패.
# handlers 섹션은 기본적으로 web.config 위임이 막혀 있어(overrideModeDefault=Deny) 경로 쓰기가 실패하면 applicationHost.config 의
# <location path="site/app"> 에서 지운다(Set-FixWebConfigProperty 와 같은 방식). 조회 실패는 "매핑 없음"으로 넘기지 않고 실패로 남긴다.
foreach ($site in $sites) {
    $Global:IisConfigQueryFailed = $false
    $paths = @(Get-IisSiteConfigPaths -SiteName $site)
    if ($Global:IisConfigQueryFailed) { $failed += "${site}: 하위 경로 조회 실패 $($Global:IisConfigQueryError)" }
    foreach ($cp in $paths) {
        try {
            $handlers = Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath $cp.PSPath -ErrorAction Stop
        } catch {
            $failed += "$($cp.Label): handler mapping 조회 실패 $($_.Exception.Message)"
            continue
        }
        $hit = @($handlers | Where-Object { $h = $_; $ssiExt | Where-Object { $h.path -ilike "*$_" } })
        foreach ($h in $hit) {
            try {
                Remove-WebConfigurationProperty -Filter "system.webServer/handlers" -PSPath $cp.PSPath -Name "." -AtElement @{name = $h.name } -ErrorAction Stop
                $applied += "$($cp.Label)($($h.name))"
            } catch {
                $first = $_.Exception.Message
                try {
                    Remove-WebConfigurationProperty -Filter "system.webServer/handlers" -PSPath "MACHINE/WEBROOT/APPHOST" -Location $cp.Label -Name "." -AtElement @{name = $h.name } -ErrorAction Stop
                    $applied += "$($cp.Label)($($h.name), applicationHost.config location)"
                } catch {
                    $failed += "$($cp.Label)($($h.name)): $first / location: $($_.Exception.Message)"
                }
            }
        }
    }
}
$Global:IisConfigQueryFailed = $false

if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "일부 SSI 핸들러 매핑 제거 실패: $($failed -join ', ')"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "SSI 핸들러 매핑 제거: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "SSI 핸들러 매핑이 없음(이미 정상)"
}
$Global:FixEvidence = ""
