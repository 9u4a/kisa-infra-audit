# WEB-12 (중) 웹 서비스 링크 사용 금지 [IIS] — 조치 [fix: confirm]
# 심볼릭 링크로 실제 콘텐츠가 구성되어 있었다면 제거 시 서비스가 깨질 수 있어 confirm 등급이다
# (checks/iis/WEB-12.sh 와 동일한 기준 — 01_unix 계열 WEB-12 와 동일한 위험 판단).

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음"; $Global:FixEvidence = ""
    return
}

$removed = @()
foreach ($site in $sites) {
    $path = Get-IisSitePhysicalPath -SiteName $site
    if (-not $path -or -not (Test-Path $path)) { continue }
    try {
        $links = Get-ChildItem -Path $path -Recurse -Depth 10 -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $_.Extension -ieq ".lnk" }
    } catch {
        $links = @()
    }
    foreach ($link in $links) {
        Backup-FixPathAndRemove -Path $link.FullName
        $removed += $link.FullName
    }
}

if ($removed.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "심볼릭 링크/바로가기 제거($($removed.Count)개): " + (($removed | Select-Object -First 5) -join '; ')
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "링크/바로가기가 없음(이미 정상)"
}
$Global:FixEvidence = ""
