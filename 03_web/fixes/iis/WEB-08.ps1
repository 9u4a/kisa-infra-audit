# WEB-08 (하) 웹 서비스 파일 업로드 및 다운로드 용량 제한 [IIS] — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 사실상 무제한(4GB 근접)으로 설정된 사이트를 IIS 기본값(30000000바이트≈28.6MB)으로 되돌린다.

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음"; $Global:FixEvidence = ""
    return
}

$unlimitedThreshold = 4000000000
$applied = @()
$failed = @()   # 쓰기 실패 - 예전엔 "대상 없음(NA)"으로 덮여 원인이 사라졌다
foreach ($site in $sites) {
    $maxLen = Get-IisConfigValue -Filter "system.webServer/security/requestFiltering/requestLimits" -Name "maxAllowedContentLength" -SiteName $site
    if ($null -ne $maxLen -and [int64]$maxLen -ge $unlimitedThreshold) {
        Set-FixWebConfigProperty -Filter "system.webServer/security/requestFiltering/requestLimits" -Name "maxAllowedContentLength" -Value 30000000 -PSPath "IIS:\Sites\$site"
        if ($Global:FixStatus -eq "APPLIED") { $applied += $site } else { $failed += "${site}: $($Global:FixDetail)" }
    }
}

if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "조치 실패: $($failed -join ' / ')$(if ($applied) { " (적용됨: $($applied -join ', '))" })"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "업로드 용량 제한을 기본값(30000000바이트)으로 되돌린 사이트: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "사실상 무제한으로 설정된 사이트가 없음(이미 정상)"
}
$Global:FixEvidence = ""
