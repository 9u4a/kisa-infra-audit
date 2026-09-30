# WEB-14 (상) 웹 서비스 경로 내 파일의 접근 통제 [IIS] — 조치 [fix: auto]

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음"; $Global:FixEvidence = ""
    return
}

$riskyRights = 'FullControl', 'Modify', 'Write'
$applied = @()
foreach ($site in $sites) {
    $path = Get-IisSitePhysicalPath -SiteName $site
    if (-not $path -or -not (Test-Path $path)) { continue }
    $acl = Get-Acl -Path $path
    $bad = $acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        $_.IdentityReference.Value -match 'Everyone|BUILTIN\\Users|Authenticated Users' -and
        ($_.FileSystemRights -match ($riskyRights -join '|'))
    }
    if (-not $bad) { continue }
    $patterns = @($bad | ForEach-Object { [regex]::Escape($_.IdentityReference.Value) })
    Remove-FixAclIdentity -Path $path -IdentityPatterns $patterns
    if ($Global:FixStatus -eq "APPLIED") { $applied += $site }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "일반 사용자 쓰기 권한을 제거한 사이트: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "일반 사용자 쓰기 권한이 있는 사이트가 없음(이미 정상)"
}
$Global:FixEvidence = ""
