# W-40 (중) 정책에 따른 시스템 로깅 설정
# 판단 기준(가이드 원문): 양호 = 감사 정책 권고 기준에 따라 감사 설정이 되어 있는 경우
# 가이드 권고 기준(로컬 정책 > 감사 정책):
#   계정 관리=실패, 계정 로그온 이벤트=성공/실패, 권한 사용=성공/실패,
#   디렉터리 서비스 액세스=실패, 로그온 이벤트=성공/실패, 정책 변경=성공/실패
# auditpol 은 시스템 로캘에 따라 하위 범주 "이름" 표시가 깨질 수 있어(콘솔 코드페이지 문제),
# 로캘 독립적인 하위 범주 GUID + CSV(/r) 출력으로 조회한다.

function Get-AuditInclusion($guid) {
    # 헤더/공백 줄이 섞여 나올 수 있으므로 위치가 아니라 대상 GUID가 포함된 줄을 직접 찾는다.
    $line = & auditpol.exe /get /subcategory:"$guid" /r 2>$null | Where-Object { $_ -like "*$guid*" } | Select-Object -First 1
    if (-not $line) { return $null }
    $cols = $line -split ','
    if ($cols.Count -ge 5) { return $cols[4].Trim() }
    return $null
}

$checks = @(
    @{ Name = "계정 관리(Other Account Management Events)"; Guid = "{0CCE923A-69AE-11D9-BED3-505054503030}"; Need = @("Failure", "Success and Failure") },
    @{ Name = "계정 로그온(Credential Validation)"; Guid = "{0CCE923F-69AE-11D9-BED3-505054503030}"; Need = @("Success and Failure") },
    @{ Name = "권한 사용(Sensitive Privilege Use)"; Guid = "{0CCE9228-69AE-11D9-BED3-505054503030}"; Need = @("Success and Failure") },
    @{ Name = "로그온(Logon)"; Guid = "{0CCE9215-69AE-11D9-BED3-505054503030}"; Need = @("Success and Failure") },
    @{ Name = "정책 변경(Audit Policy Change)"; Guid = "{0CCE922F-69AE-11D9-BED3-505054503030}"; Need = @("Success and Failure") }
)

$evidence = @()
$violations = @()
foreach ($c in $checks) {
    $setting = Get-AuditInclusion $c.Guid
    $evidence += "$($c.Name): $setting"
    if (-not $setting -or ($c.Need -notcontains $setting)) { $violations += $c.Name }
}

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-40" -Status "GOOD" -Detail "감사 정책 권고 기준에 따라 주요 감사 항목이 설정되어 있음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-40" -Status "VULN" -Detail ("권고 기준 미충족 감사 항목: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
}
