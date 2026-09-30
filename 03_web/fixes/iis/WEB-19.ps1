# WEB-19 (중) 웹 서비스 SSI(Server Side Includes) 사용 제한 [IIS] — 조치 [fix: auto]
# checks/iis/WEB-19.ps1 이 찾아낸 .stm/.shtm/.shtml 핸들러 매핑을 제거한다. 컬렉션 원소
# 제거라 표준 webconfig 백업/원복 대상이 아니다(WEB-13과 동일한 한계, 03_web/CLAUDE.md 참고).

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

foreach ($site in $sites) {
    try {
        $handlers = Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath "IIS:\Sites\$site" -ErrorAction Stop
    } catch {
        $handlers = @()
    }
    $hit = @($handlers | Where-Object { $h = $_; $ssiExt | Where-Object { $h.path -ilike "*$_" } })
    foreach ($h in $hit) {
        try {
            Remove-WebConfigurationProperty -Filter "system.webServer/handlers" -PSPath "IIS:\Sites\$site" -Name "." -AtElement @{name = $h.name } -ErrorAction Stop
            $applied += "$site($($h.name))"
        } catch {
            $failed += "$site($($h.name))"
        }
    }
}

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
