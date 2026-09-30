# WEB-26 (중) 로그 디렉터리 및 파일 권한 설정 [IIS] — 조치 [fix: auto]

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
$checkedDirs = @{}
foreach ($site in $sites) {
    $logDir = Get-IisConfigValue -Filter "system.applicationHost/sites/site[@name='$site']/logFile" -Name "directory" -SiteName ""
    if (-not $logDir) { $logDir = Join-Path $env:SystemDrive "inetpub\logs\LogFiles" }
    $logDir = [System.Environment]::ExpandEnvironmentVariables($logDir)
    if ($checkedDirs.ContainsKey($logDir)) { continue }
    $checkedDirs[$logDir] = $true
    if (-not (Test-Path $logDir)) { continue }

    $acl = Get-Acl -Path $logDir
    $bad = $acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -match 'Everyone|BUILTIN\\Users|Authenticated Users'
    }
    if (-not $bad) { continue }
    $patterns = @($bad | ForEach-Object { [regex]::Escape($_.IdentityReference.Value) })
    Remove-FixAclIdentity -Path $logDir -IdentityPatterns $patterns
    if ($Global:FixStatus -eq "APPLIED") { $applied += $logDir }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "로그 디렉터리에서 일반 사용자 접근 권한 제거: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "일반 사용자 접근 권한이 있는 로그 디렉터리가 없음(이미 정상)"
}
$Global:FixEvidence = ""
