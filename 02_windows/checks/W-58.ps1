# W-58 (중) 사용자별 홈 디렉터리 권한 설정
# 판단 기준(가이드 원문): 양호 = 홈 디렉터리에 Everyone 권한이 없는 경우(All Users/Default 제외)
#                        취약 = Everyone 권한이 있는 경우

$usersRoot = Join-Path $env:SystemDrive "Users"
if (-not (Test-Path $usersRoot)) {
    return New-CheckResult -Code "W-58" -Status "ERROR" -Detail "$usersRoot 디렉터리를 찾을 수 없음"
}

$exclude = @("Public", "Default", "Default User", "All Users")
$dirs = Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $exclude -notcontains $_.Name }

$violations = @()
$evidence = @()
foreach ($d in $dirs) {
    try {
        $acl = Get-Acl -Path $d.FullName -ErrorAction Stop
        $everyone = $acl.Access | Where-Object { $_.IdentityReference -match "Everyone" -and $_.AccessControlType -eq "Allow" }
        $evidence += "$($d.Name): " + (($acl.Access | ForEach-Object { "$($_.IdentityReference)=$($_.FileSystemRights)" }) -join "; ")
        if ($everyone) { $violations += $d.Name }
    } catch {
        $evidence += "$($d.Name): ACL 조회 실패"
    }
}

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-58" -Status "GOOD" -Detail "사용자 홈 디렉터리에 Everyone 권한이 없음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-58" -Status "VULN" -Detail ("Everyone 권한이 있는 홈 디렉터리: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
}
