# WEB-14 (상) 웹 서비스 경로 내 파일의 접근 통제 [IIS]
# 판단 기준(가이드 원문): 양호 = 주요 설정 파일/디렉터리에 불필요한 접근 권한이 없는 경우
#                        취약 = 불필요한 접근 권한이 부여된 경우
# 자동화 범위: 사이트 physicalPath 최상위 NTFS ACL 에서 Everyone/Users/Authenticated Users 에게
# 쓰기(Write/Modify/FullControl) 권한이 허용되어 있는지 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-14" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-14" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$riskyRights = 'FullControl', 'Modify', 'Write'
$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $path = Get-IisSitePhysicalPath -SiteName $site
    if (-not $path -or -not (Test-Path $path)) {
        $evid += "[$site] 물리 경로를 찾을 수 없음: $path"
        continue
    }
    try {
        $acl = Get-Acl -Path $path -ErrorAction Stop
    } catch {
        $evid += "[$site] ACL 조회 실패: $($_.Exception.Message)"
        continue
    }
    $bad = $acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        $_.IdentityReference.Value -match 'Everyone|BUILTIN\\Users|Authenticated Users' -and
        ($_.FileSystemRights -match ($riskyRights -join '|'))
    }
    $evid += "[$site] $path 의 위험 ACE: $((@($bad | ForEach-Object { "$($_.IdentityReference):$($_.FileSystemRights)" })) -join '; ')"
    if ($bad) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-14" -Status "VULN" -Detail "일반 사용자 그룹에 쓰기 권한이 허용된 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-14" -Status "GOOD" -Detail "모든 사이트 경로에 일반 사용자 쓰기 권한이 없음" -Evidence ($evid -join "`n")
