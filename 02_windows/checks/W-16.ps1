# W-16 (상) 공유 권한 및 사용자 그룹 설정
# 판단 기준(가이드 원문): 양호 = 일반 공유 디렉터리가 없거나 Everyone 권한이 없는 경우
#                        취약 = 일반 공유 디렉터리 접근 권한에 Everyone 이 있는 경우
# 기본 관리 공유(C$, ADMIN$, IPC$ 등 $ 로 끝나는 공유)는 W-17 에서 별도로 다루므로 제외한다.

try {
    $shares = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'print$' }
} catch {
    return New-CheckResult -Code "W-16" -Status "ERROR" -Detail "Get-SmbShare 실행 실패: $($_.Exception.Message)"
}

if (-not $shares -or $shares.Count -eq 0) {
    return New-CheckResult -Code "W-16" -Status "GOOD" -Detail "일반(비관리용) 공유 디렉터리가 존재하지 않음"
}

$violations = @()
$evidence = @()
foreach ($s in $shares) {
    $access = Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue
    $everyone = $access | Where-Object { $_.AccountName -match "Everyone" }
    $evidence += "공유 '$($s.Name)' ($($s.Path)): " + (($access | ForEach-Object { "$($_.AccountName)=$($_.AccessRight)" }) -join "; ")
    if ($everyone) { $violations += $s.Name }
}

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-16" -Status "GOOD" -Detail "일반 공유 디렉터리에 Everyone 권한이 없음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-16" -Status "VULN" -Detail ("Everyone 권한이 부여된 공유: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
}
