# W-22 (상) FTP 디렉토리 접근권한 설정
# 판단 기준(가이드 원문): 양호 = FTP 홈 디렉터리에 Everyone 권한이 없는 경우(또는 FTP 미사용)
#                        취약 = Everyone 권한이 있는 경우
# W-R3: FTP 사이트 경로는 보통 %SystemDrive%\inetpub\ftproot 처럼 환경변수가 들어 있는데 예전에는 펼치지 않아
# Get-Acl 이 항상 실패했고, 그 실패를 GOOD 으로 넘겼다. 경로를 펼치고, ACL 조회 실패는 ERROR. Everyone 은
# SID(S-1-1-0)로 비교한다(비영문 OS).

# 서비스 조회 실패(권한 부족 등)를 "FTP 미사용"으로 읽지 않는다(S6)
try { $svc = Get-ServiceChecked -Name "FTPSVC" }
catch { return New-CheckResult -Code "W-22" -Status "ERROR" -Detail "FTP(FTPSVC) 서비스 상태를 조회하지 못함: $($_.Exception.Message)" }
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-22" -Status "GOOD" -Detail "FTP 서비스를 사용하지 않음"
}

if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    return New-CheckResult -Code "W-22" -Status "MANUAL" -Detail "FTP 서비스가 구동 중이나 WebAdministration 모듈이 없어 홈 디렉터리 권한을 자동 조회할 수 없음 — IIS 관리자에서 수동 확인 필요"
}

Import-Module WebAdministration -ErrorAction SilentlyContinue
try {
    $sites = Get-Website -ErrorAction Stop | Where-Object { $_.Bindings.Collection.protocol -contains "ftp" }
} catch {
    return New-CheckResult -Code "W-22" -Status "MANUAL" -Detail "FTP 사이트 목록 조회 실패: $($_.Exception.Message)"
}

if (-not $sites) {
    return New-CheckResult -Code "W-22" -Status "NA" -Detail "FTP 서비스는 구동 중이나 등록된 FTP 사이트가 없음"
}

$violations = @()
$unverified = @()
$evidence = @()
foreach ($site in $sites) {
    $path = $site.PhysicalPath
    if (-not $path) {
        $unverified += $site.Name
        $evidence += "$($site.Name): 홈 디렉터리 경로 없음"
        continue
    }
    $path = [System.Environment]::ExpandEnvironmentVariables($path)
    try {
        $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
        $everyone = Get-AclAllowRulesForSids -Acl $acl -Sids @('S-1-1-0')
        $evidence += "$($site.Name) ($path): " + (($acl.Access | ForEach-Object { "$($_.IdentityReference)=$($_.FileSystemRights)" }) -join "; ")
        if ($everyone.Count -gt 0) { $violations += $site.Name }
    } catch {
        $unverified += $site.Name
        $evidence += "$($site.Name) ($path): ACL 조회 실패 - $($_.Exception.Message)"
    }
}

if ($violations.Count -gt 0) {
    return New-CheckResult -Code "W-22" -Status "VULN" -Detail ("Everyone 권한이 있는 FTP 사이트: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($unverified.Count -gt 0) {
    return New-CheckResult -Code "W-22" -Status "ERROR" -Detail ("홈 디렉터리 권한을 확인하지 못한 FTP 사이트: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-22" -Status "GOOD" -Detail "FTP 홈 디렉터리에 Everyone 권한이 없음" -Evidence ($evidence -join "`n")
}
