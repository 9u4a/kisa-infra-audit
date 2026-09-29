# WEB-12 (중) 웹 서비스 링크 사용 금지 [IIS]
# 판단 기준(가이드 원문): 양호 = 심볼릭 링크/바로가기 등 링크 사용을 허용하지 않는 경우
#                        취약 = 허용하는 경우
# 자동화 범위: 사이트 physicalPath 하위에서 NTFS 리파스 포인트(심볼릭 링크/정션)와 Windows
# 바로가기(.lnk) 파일 존재 여부를 확인한다. 링크가 순환 구조를 이룰 수 있어 재귀 깊이를
# 제한한다(-Depth 10).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-12" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-12" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $path = Get-IisSitePhysicalPath -SiteName $site
    if (-not $path -or -not (Test-Path $path)) {
        $evid += "[$site] 물리 경로를 찾을 수 없음: $path"
        continue
    }
    try {
        $links = Get-ChildItem -Path $path -Recurse -Depth 10 -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $_.Extension -ieq ".lnk" }
    } catch {
        $links = @()
    }
    if ($links -and $links.Count -gt 0) {
        $vuln += $site
        $evid += "[$site] 링크/바로가기 발견: $(($links | Select-Object -First 5 -ExpandProperty FullName) -join '; ')"
    } else {
        $evid += "[$site] 링크/바로가기 없음"
    }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-12" -Status "VULN" -Detail "심볼릭 링크/바로가기가 존재하는 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-12" -Status "GOOD" -Detail "모든 사이트에서 링크/바로가기가 발견되지 않음" -Evidence ($evid -join "`n")
