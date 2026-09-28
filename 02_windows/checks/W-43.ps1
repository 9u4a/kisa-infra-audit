# W-43 (중) 이벤트 로그 파일 접근 통제 설정
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리 접근 권한에 Everyone 이 없는 경우
#                        취약 = Everyone 권한이 있는 경우
# 최신 Windows 의 실제 이벤트 로그 위치는 %systemroot%\System32\winevt\Logs (가이드의
# system32\config 는 레거시 경로) 이므로 두 경로를 모두 확인한다.

$paths = @(
    (Join-Path $env:SystemRoot "System32\winevt\Logs"),
    (Join-Path $env:SystemRoot "System32\config")
) | Where-Object { Test-Path $_ }

if ($paths.Count -eq 0) {
    return New-CheckResult -Code "W-43" -Status "ERROR" -Detail "로그 디렉터리를 찾을 수 없음"
}

$violations = @()
$evidence = @()
foreach ($p in $paths) {
    try {
        $acl = Get-Acl -Path $p -ErrorAction Stop
        $everyone = $acl.Access | Where-Object { $_.IdentityReference -match "Everyone" -and $_.AccessControlType -eq "Allow" }
        $evidence += "$p : " + (($acl.Access | ForEach-Object { "$($_.IdentityReference)=$($_.FileSystemRights)" }) -join "; ")
        if ($everyone) { $violations += $p }
    } catch {
        $evidence += "$p : ACL 조회 실패"
    }
}

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-43" -Status "GOOD" -Detail "로그 디렉터리 접근 권한에 Everyone 이 없음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-43" -Status "VULN" -Detail ("Everyone 권한이 부여된 로그 디렉터리: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
}
