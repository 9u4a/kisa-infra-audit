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
        # WEB-R7: ACL 조회 실패를 건너뛴 채 GOOD 을 내지 않는다(실패 표시 → run.ps1 이 GOOD 을 ERROR 로)
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "ACL 조회 실패: $($_.Exception.Message)"
        $evid += "[$site] $logDir ACL 조회 실패: $($_.Exception.Message)"
        continue
    }
    # 이름 패턴 대신 SID(Everyone S-1-1-0, Users S-1-5-32-545, Authenticated Users S-1-5-11)로 비교한다(비영문 OS)
    $bad = @(Get-AclAllowRulesForSids -Acl $acl -Sids @('S-1-1-0', 'S-1-5-32-545', 'S-1-5-11'))
    $evid += "[$site] $logDir 일반 사용자 ACE: $(if ($bad.Count -gt 0) { (@($bad | ForEach-Object { "$(ConvertFrom-Sid $_.IdentityReference.Value):$($_.FileSystemRights)" })) -join '; ' } else { '없음' })"
    if ($bad.Count -gt 0) { $vuln += $logDir }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-26" -Status "VULN" -Detail "일반 사용자 접근이 허용된 로그 디렉터리: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-26" -Status "GOOD" -Detail "로그 디렉터리에 일반 사용자 접근 권한이 없음" -Evidence ($evid -join "`n")
