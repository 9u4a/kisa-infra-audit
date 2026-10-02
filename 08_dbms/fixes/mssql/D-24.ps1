# D-24 (상) Registry Procedure 권한 제한 [MSSQL] — 조치 [fix: auto]
# checks/mssql/D-24.ps1 이 찾아낸 (프로시저, principal) 조합에서 실행 권한을 회수한다.

$procList = @('xp_regread', 'xp_regwrite', 'xp_regdeletekey', 'xp_regdeletevalue', 'xp_regenumvalues', 'xp_regremovemultistring', 'xp_regaddmultistring')
$procsInClause = ($procList | ForEach-Object { "'$_'" }) -join ','
$sql = "SET NOCOUNT ON; SELECT o.name, dp.name FROM master.sys.database_permissions p JOIN master.sys.objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name IN ($procsInClause) AND dp.name IN ('public','guest') AND p.state = 'G';"
$out = Invoke-MssqlQuery -Sql $sql
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "MSSQL 연결/쿼리 실패: $err"; $Global:FixEvidence = ""
    return
}
if (-not $out) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "레지스트리 프로시저 비인가 권한이 없음(이미 정상)"; $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($row in @($out)) {
    $fields = $row -split '\|'
    if ($fields.Count -lt 2) { continue }
    $proc = $fields[0].Trim()
    $principal = $fields[1].Trim()
    if (-not $proc -or -not $principal) { continue }
    Add-FixDbRollback -Sql "USE master; GRANT EXECUTE ON $proc TO [$principal];"
    Invoke-MssqlQuery -Sql "USE master; REVOKE EXECUTE ON $proc FROM [$principal];" | Out-Null
    $applied += "$proc->$principal"
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "레지스트리 프로시저 권한 회수: $($applied -join ', ')"
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "권한 회수 실패(결과 파싱 실패 가능)"
}
$Global:FixEvidence = ""
