# W-22 (상) FTP 디렉토리 접근권한 설정
# 판단 기준(가이드 원문): 양호 = FTP 홈 디렉터리에 Everyone 권한이 없는 경우(또는 FTP 미사용)
#                        취약 = Everyone 권한이 있는 경우

$svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
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
$evidence = @()
foreach ($site in $sites) {
    $path = $site.PhysicalPath
    if (-not $path) { continue }
    try {
        $acl = Get-Acl -Path $path -ErrorAction Stop
        $everyone = $acl.Access | Where-Object { $_.IdentityReference -match "Everyone" }
        $evidence += "$($site.Name) ($path): " + (($acl.Access | ForEach-Object { "$($_.IdentityReference)=$($_.FileSystemRights)" }) -join "; ")
        if ($everyone) { $violations += $site.Name }
    } catch {
        $evidence += "$($site.Name) ($path): ACL 조회 실패"
    }
}

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-22" -Status "GOOD" -Detail "FTP 홈 디렉터리에 Everyone 권한이 없음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-22" -Status "VULN" -Detail ("Everyone 권한이 있는 FTP 사이트: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
}
