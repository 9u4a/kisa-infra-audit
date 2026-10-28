# W-43 (중) 이벤트 로그 파일 접근 통제 설정
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리 접근 권한에 Everyone 이 없는 경우
#                        취약 = Everyone 권한이 있는 경우
# 최신 Windows 의 실제 이벤트 로그 위치는 %systemroot%\System32\winevt\Logs (가이드의
# system32\config 는 레거시 경로) 이므로 두 경로를 모두 확인한다.
# W-R3: ACL 조회 실패를 예전에는 GOOD 으로 넘겼다 - ERROR. Everyone 은 SID(S-1-1-0)로 비교한다(비영문 OS).

$paths = @(
    (Join-Path $env:SystemRoot "System32\winevt\Logs"),
    (Join-Path $env:SystemRoot "System32\config")
) | Where-Object { Test-Path $_ }

if ($paths.Count -eq 0) {
    return New-CheckResult -Code "W-43" -Status "ERROR" -Detail "로그 디렉터리를 찾을 수 없음"
}

$violations = @()
$unverified = @()
$evidence = @()
foreach ($p in $paths) {
    try {
        $acl = Get-Acl -LiteralPath $p -ErrorAction Stop
        $everyone = Get-AclAllowRulesForSids -Acl $acl -Sids @('S-1-1-0')
        $evidence += "$p : " + (($acl.Access | ForEach-Object { "$($_.IdentityReference)=$($_.FileSystemRights)" }) -join "; ")
        if ($everyone.Count -gt 0) { $violations += $p }
    } catch {
        $unverified += $p
        $evidence += "$p : ACL 조회 실패 - $($_.Exception.Message)"
    }
}

if ($violations.Count -gt 0) {
    return New-CheckResult -Code "W-43" -Status "VULN" -Detail ("Everyone 권한이 부여된 로그 디렉터리: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($unverified.Count -gt 0) {
    return New-CheckResult -Code "W-43" -Status "ERROR" -Detail ("ACL 을 조회하지 못한 로그 디렉터리: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-43" -Status "GOOD" -Detail "로그 디렉터리 접근 권한에 Everyone 이 없음" -Evidence ($evidence -join "`n")
}
