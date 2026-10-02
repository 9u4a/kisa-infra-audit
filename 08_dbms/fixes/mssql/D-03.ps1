# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [MSSQL] — 조치 [fix: confirm]
# checks/mssql/D-03.ps1: 취약 = CHECK_POLICY 가 적용되지 않은 SQL 로그인 존재. 해당 로그인에
# CHECK_POLICY=ON 을 적용한다(기존 비밀번호를 바꾸지 않음 - 다음 비밀번호 변경부터 정책 적용).

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name FROM sys.sql_logins WHERE is_policy_checked = 0;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "MSSQL 연결/쿼리 실패: $err"; $Global:FixEvidence = ""
    return
}
if (-not $out) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "CHECK_POLICY 가 적용되지 않은 로그인이 없음(이미 정상)"; $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($row in @($out)) {
    $name = $row.Trim()
    if (-not $name) { continue }
    Add-FixDbRollback -Sql "ALTER LOGIN [$name] WITH CHECK_POLICY = OFF;"
    Invoke-MssqlQuery -Sql "ALTER LOGIN [$name] WITH CHECK_POLICY = ON;" | Out-Null
    $applied += $name
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "CHECK_POLICY 를 적용한 로그인: $($applied -join ', ')"
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "CHECK_POLICY 적용 실패"
}
$Global:FixEvidence = ""
