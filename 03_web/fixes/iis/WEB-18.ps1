# WEB-18 (상) 웹 서비스 WebDAV 비활성화 [IIS] — 조치 [fix: auto]

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
$failed = @()   # 쓰기 실패 - 예전엔 "대상 없음(NA)"으로 덮여 원인이 사라졌다
foreach ($site in $sites) {
    $enabled = Get-IisConfigValue -Filter "system.webServer/webdav/authoring" -Name "enabled" -SiteName $site
    if ($enabled -eq $true) {
        Set-FixWebConfigProperty -Filter "system.webServer/webdav/authoring" -Name "enabled" -Value $false -PSPath "IIS:\Sites\$site"
        if ($Global:FixStatus -eq "APPLIED") { $applied += $site } else { $failed += "${site}: $($Global:FixDetail)" }
    }
}

if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "조치 실패: $($failed -join ' / ')$(if ($applied) { " (적용됨: $($applied -join ', '))" })"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "WebDAV 를 비활성화한 사이트: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "WebDAV 가 활성화된 사이트가 없음(이미 정상)"
}
$Global:FixEvidence = ""
