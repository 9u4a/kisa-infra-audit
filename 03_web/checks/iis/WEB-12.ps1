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

$vuln = @(); $evid = @(); $manual = @()
foreach ($site in $sites) {
    $path = Get-IisSitePhysicalPath -SiteName $site
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        # WEB-R7: 경로를 확인하지 못한 사이트를 건너뛴 채 GOOD 을 내지 않는다(실패 표시 → run.ps1 이 GOOD 을 ERROR 로)
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "physicalPath ($site): 경로를 찾을 수 없음($path)"
        $evid += "[$site] 물리 경로를 찾을 수 없음: $path"
        continue
    }
    # UNC(\\서버\공유, DFS) 콘텐츠는 원격 파일 서버 전체를 순회하게 되므로 검사하지 않고 수동 확인으로 남긴다.
    if ($path -like '\\*') {
        $manual += $site
        $evid += "[$site] 원격 경로($path)라 운영 부하 방지를 위해 순회하지 않음 - 수동 확인 필요"
        continue
    }
    # 링크(정션/심볼릭) 안으로는 들어가지 않는다 - PS 5.1 -Recurse 는 링크를 따라가 다른 폴더·볼륨까지
    # 순회했다. 직접 큐로 순회하며 링크는 "발견"만 하고, 검사 항목 수에 상한을 둔다.
    $links = @(); $visited = 0; $limit = 20000; $truncated = $false
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue(@($path, 0))
    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        $lsErr = $null
        $children = @(Get-ChildItem -LiteralPath $cur[0] -Force -ErrorAction SilentlyContinue -ErrorVariable lsErr)
        if ($lsErr) {
            # WEB-R7: 읽지 못한 폴더(권한 부족 등)가 있으면 "링크 없음"을 확정할 수 없다
            $Global:IisConfigQueryFailed = $true
            $Global:IisConfigQueryError = "$($cur[0]) 하위 목록 조회 실패: $($lsErr[0].Exception.Message)"
        }
        foreach ($it in $children) {
            $visited++
            if ($visited -gt $limit) { $truncated = $true; break }
            $isLink = [bool]($it.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($isLink -or $it.Extension -ieq ".lnk") { $links += $it; continue }
            if ($it.PSIsContainer -and $cur[1] -lt 10) { $queue.Enqueue(@($it.FullName, ($cur[1] + 1))) }
        }
        if ($truncated) { break }
    }
    if ($truncated -and $links.Count -eq 0) {
        $manual += $site
        $evid += "[$site] 항목이 많아 처음 $limit 개만 검사함(링크 없음) - 나머지는 수동 확인 필요"
        continue
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
if ($manual.Count -gt 0) {
    return New-CheckResult -Code "WEB-12" -Status "MANUAL" -Detail "일부 사이트는 원격 경로이거나 항목이 많아 전체 검사하지 못함: $($manual -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-12" -Status "GOOD" -Detail "모든 사이트에서 링크/바로가기가 발견되지 않음" -Evidence ($evid -join "`n")
