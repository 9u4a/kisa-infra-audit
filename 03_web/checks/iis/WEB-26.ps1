# WEB-26 (중) 로그 디렉터리 및 파일 권한 설정 [IIS]
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리/파일에 일반 사용자 접근 권한이 없는 경우
#                        취약 = 일반 사용자 접근 권한이 있는 경우
# 자동화 범위: 가이드는 IIS 로그를 C:\Windows\System32\LogFiles 로 안내하지만, 실제로는 사이트별
# logFile.directory(기본 %SystemDrive%\inetpub\logs\LogFiles) 설정을 따른다. 사이트별 실제 로그
# 디렉터리의 NTFS ACL 에서 Everyone/Users/Authenticated Users 접근 허용 여부를 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-26" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
$sites = Get-IisSiteNames
if (-not $sites -or $sites.Count -eq 0) {
    return New-CheckResult -Code "WEB-26" -Status "NA" -Detail "구성된 IIS 웹사이트가 없음"
}

$vuln = @(); $evid = @(); $checkedDirs = @{}
foreach ($site in $sites) {
    $logDir = Get-IisConfigValue -Filter "system.applicationHost/sites/site[@name='$site']/logFile" -Name "directory" -SiteName ""
    if (-not $logDir) {
        $logDir = Join-Path $env:SystemDrive "inetpub\logs\LogFiles"
    }
    $logDir = [System.Environment]::ExpandEnvironmentVariables($logDir)

    if ($checkedDirs.ContainsKey($logDir)) { continue }
    $checkedDirs[$logDir] = $true

    if (-not (Test-Path $logDir)) {
        $evid += "[$site] 로그 디렉터리 없음(아직 로그 미생성으로 추정): $logDir"
        continue
    }
    try {
        $acl = Get-Acl -Path $logDir -ErrorAction Stop
    } catch {
        $evid += "[$site] $logDir ACL 조회 실패: $($_.Exception.Message)"
        continue
    }
    $bad = $acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        $_.IdentityReference.Value -match 'Everyone|BUILTIN\\Users|Authenticated Users'
    }
    $evid += "[$site] $logDir 일반 사용자 ACE: $(if ($bad) { (@($bad | ForEach-Object { "$($_.IdentityReference):$($_.FileSystemRights)" })) -join '; ' } else { '없음' })"
    if ($bad) { $vuln += $logDir }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-26" -Status "VULN" -Detail "일반 사용자 접근이 허용된 로그 디렉터리: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-26" -Status "GOOD" -Detail "로그 디렉터리에 일반 사용자 접근 권한이 없음" -Evidence ($evid -join "`n")
