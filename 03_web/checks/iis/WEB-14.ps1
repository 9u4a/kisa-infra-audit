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

$vuln = @(); $evid = @()
foreach ($site in $sites) {
    $path = Get-IisSitePhysicalPath -SiteName $site
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "physicalPath ($site): 경로를 찾을 수 없음($path)"
        $evid += "[$site] 물리 경로를 찾을 수 없음: $path"
        continue
    }
    try {
        $acl = Get-Acl -Path $path -ErrorAction Stop
    } catch {
        # WEB-R7: ACL 조회 실패를 건너뛴 채 GOOD 을 내지 않는다(실패 표시 → run.ps1 이 GOOD 을 ERROR 로)
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "ACL 조회 실패: $($_.Exception.Message)"
        $evid += "[$site] ACL 조회 실패: $($_.Exception.Message)"
        continue
    }
    # 이름 패턴 대신 SID(Everyone S-1-1-0, Users S-1-5-32-545, Authenticated Users S-1-5-11)로 비교하고(비영문 OS),
    # 쓰기 계열 권한은 비트로 본다 - FileSystemRights 가 일반 권한(GenericWrite/GenericAll)이면 숫자로만 표시돼
    # 이름 패턴('Write|Modify|FullControl')에 걸리지 않았다.
    # WriteData 0x2, AppendData 0x4, WriteExtendedAttributes 0x10, WriteAttributes 0x100, Delete 0x10000,
    # ChangePermissions 0x40000, TakeOwnership 0x80000, GenericAll 0x10000000, GenericWrite 0x40000000
    $writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
    $bad = @(Get-AclAllowRulesForSids -Acl $acl -Sids @('S-1-1-0', 'S-1-5-32-545', 'S-1-5-11') |
        Where-Object { ([int64]$_.FileSystemRights -band $writeMask) -ne 0 })
    $evid += "[$site] $path 의 위험 ACE: $((@($bad | ForEach-Object { "$(ConvertFrom-Sid $_.IdentityReference.Value):$($_.FileSystemRights)" })) -join '; ')"
    if ($bad.Count -gt 0) { $vuln += $site }
}

if ($vuln.Count -gt 0) {
    return New-CheckResult -Code "WEB-14" -Status "VULN" -Detail "일반 사용자 그룹에 쓰기 권한이 허용된 사이트: $($vuln -join ', ')" -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "WEB-14" -Status "GOOD" -Detail "모든 사이트 경로에 일반 사용자 쓰기 권한이 없음" -Evidence ($evid -join "`n")
