# W-22 (상) FTP 디렉토리 접근권한 설정 [fix: auto]
# checks/W-22.ps1: 양호 = FTP 홈 디렉터리에 Everyone 권한이 없는 경우.
# WebAdministration 으로 FTP 사이트의 실제 경로를 찾아 Everyone ACE 만 제거한다.

if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "WebAdministration 모듈이 없어 FTP 사이트 경로를 조회할 수 없음"
    $Global:FixEvidence = ""
    return
}
Import-Module WebAdministration -ErrorAction SilentlyContinue

try {
    $sites = Get-Website -ErrorAction Stop | Where-Object { $_.Bindings.Collection.protocol -contains "ftp" }
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "FTP 사이트 목록 조회 실패: $($_.Exception.Message)"
    $Global:FixEvidence = ""
    return
}

if (-not $sites) {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "등록된 FTP 사이트가 없음"
    $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($site in $sites) {
    if (-not $site.PhysicalPath -or -not (Test-Path $site.PhysicalPath)) { continue }
    Remove-FixAclIdentity -Path $site.PhysicalPath -IdentityPatterns @("Everyone")
    if ($Global:FixStatus -eq "APPLIED") { $applied += $site.Name }
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "FTP 사이트 홈 디렉터리에서 Everyone 권한 제거: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "Everyone 권한이 있는 FTP 사이트가 없음(이미 정상)"
}
