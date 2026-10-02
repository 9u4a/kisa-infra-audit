# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [MSSQL] — 조치 [fix: auto]
# checks/mssql/D-11.ps1 과 동일한 조건으로 찾아낸 (principal, object, permission) 을 회수한다.
# USE 대신 master.sys.* 3-part naming 을 쓰는 이유는 checks/mssql/D-11.ps1 주석 참고.

$sql = "SET NOCOUNT ON; SELECT dp.name, o.name, p.permission_name FROM master.sys.database_permissions p JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id JOIN master.sys.objects o ON p.major_id = o.object_id WHERE o.is_ms_shipped = 1 AND dp.name IN ('public','guest') AND p.state = 'G' AND o.name NOT IN ('spt_fallback_db','spt_fallback_dev','spt_fallback_usg','spt_values','spt_monitor');"
$out = Invoke-MssqlQuery -Sql $sql
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "MSSQL 연결/쿼리 실패: $err"; $Global:FixEvidence = ""
    return
}
if (-not $out) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "public/guest 에게 부여된 시스템 객체 권한이 없음(이미 정상)"; $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($row in @($out)) {
    $fields = $row -split '\|'
    if ($fields.Count -lt 3) { continue }
    $principal = $fields[0].Trim()
    $obj = $fields[1].Trim()
    $perm = $fields[2].Trim()
    if (-not $principal -or -not $obj -or -not $perm) { continue }
    Add-FixDbRollback -Sql "USE master; GRANT $perm ON OBJECT::$obj TO [$principal];"
    Invoke-MssqlQuery -Sql "USE master; REVOKE $perm ON OBJECT::$obj FROM [$principal];" | Out-Null
    $applied += "$principal($obj`:$perm)"
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "시스템 객체 권한 회수: $($applied -join ', ')"
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "권한 회수 실패(결과 파싱 실패 가능)"
}
$Global:FixEvidence = ""
