# WEB-13 (상) 웹 서비스 설정 파일 노출 제한 [IIS] — 조치 [fix: auto]
# checks/iis/WEB-13.ps1 이 확인하는 hiddenSegments 컬렉션에 "web.config" 항목을 추가한다.
# 컬렉션에 원소를 추가/제거하는 작업은 Set-FixWebConfigProperty(단일 값 설정)로 표현할 수
# 없어 Add-WebConfigurationProperty 를 직접 쓴다 - 이 항목은 표준 webconfig 백업/원복 대상이
# 아니라는 한계가 있다(03_web/CLAUDE.md 참고, 실패해도 사이트 동작 자체에는 영향 없음).

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음"; $Global:FixEvidence = ""
    return
}

$applied = @()
$failed = @()
foreach ($site in $sites) {
    try {
        $hidden = Get-WebConfiguration -Filter "system.webServer/security/requestFiltering/hiddenSegments/add" -PSPath "IIS:\Sites\$site" -ErrorAction Stop
        $names = @($hidden | ForEach-Object { $_.segment })
    } catch {
        $names = @()
    }
    if ($names -contains "web.config") { continue }
    try {
        Add-WebConfigurationProperty -Filter "system.webServer/security/requestFiltering/hiddenSegments" -PSPath "IIS:\Sites\$site" -Name "." -Value @{segment = "web.config" } -ErrorAction Stop
        $applied += $site
    } catch {
        $failed += $site
    }
}

if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "일부 사이트에서 hiddenSegments 추가 실패: $($failed -join ', ')"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "web.config 를 hiddenSegments 에 추가한 사이트: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "이미 모든 사이트에서 web.config 가 보호되고 있음"
}
$Global:FixEvidence = ""
