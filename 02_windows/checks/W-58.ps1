# W-58 (중) 사용자별 홈 디렉터리 권한 설정
# 판단 기준(가이드 원문): 양호 = 홈 디렉터리에 Everyone 권한이 없는 경우(All Users/Default 제외)
#                        취약 = Everyone 권한이 있는 경우
# W-R3: 홈 디렉터리 목록·ACL 조회 실패를 예전에는 GOOD 으로 넘겼다 - ERROR. Everyone 은 SID(S-1-1-0)로 비교한다.

$usersRoot = Join-Path $env:SystemDrive "Users"
if (-not (Test-Path $usersRoot)) {
    return New-CheckResult -Code "W-58" -Status "ERROR" -Detail "$usersRoot 디렉터리를 찾을 수 없음"
}

$exclude = @("Public", "Default", "Default User", "All Users")
try {
    $dirs = @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction Stop | Where-Object {
            $exclude -notcontains $_.Name -and -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) })
} catch {
    return New-CheckResult -Code "W-58" -Status "ERROR" -Detail "$usersRoot 하위 목록 조회 실패: $($_.Exception.Message)"
}

$violations = @()
$unverified = @()
$evidence = @()
foreach ($d in $dirs) {
    try {
        $acl = Get-Acl -LiteralPath $d.FullName -ErrorAction Stop
        $everyone = Get-AclAllowRulesForSids -Acl $acl -Sids @('S-1-1-0')
        $evidence += "$($d.Name): " + (($acl.Access | ForEach-Object { "$($_.IdentityReference)=$($_.FileSystemRights)" }) -join "; ")
        if ($everyone.Count -gt 0) { $violations += $d.Name }
    } catch {
        $unverified += $d.Name
        $evidence += "$($d.Name): ACL 조회 실패 - $($_.Exception.Message)"
    }
}

if ($violations.Count -gt 0) {
    return New-CheckResult -Code "W-58" -Status "VULN" -Detail ("Everyone 권한이 있는 홈 디렉터리: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($unverified.Count -gt 0) {
    return New-CheckResult -Code "W-58" -Status "ERROR" -Detail ("ACL 을 조회하지 못한 홈 디렉터리: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-58" -Status "GOOD" -Detail "사용자 홈 디렉터리에 Everyone 권한이 없음" -Evidence ($evidence -join "`n")
}
