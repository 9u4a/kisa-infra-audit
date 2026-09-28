# D-24 (상) Registry Procedure 권한 제한 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 레지스트리 관련 확장 저장 프로시저가 DBA 외 guest/public 에게
#                        부여되지 않은 경우 / 취약 = 부여된 경우

$procList = @('xp_regread','xp_regwrite','xp_regdeletekey','xp_regdeletevalue','xp_regenumvalues','xp_regremovemultistring','xp_regaddmultistring')
$procsInClause = ($procList | ForEach-Object { "'$_'" }) -join ','
# "USE master;" 는 sqlcmd가 "Changed database context..." 메시지를 결과에 섞어 항상 결과가
# 있는 것처럼 오판되게 만든다(D-11에서 실기 테스트로 확인한 버그) - 3-part naming 으로 회피.
$sql = "SET NOCOUNT ON; SELECT o.name, dp.name FROM master.sys.database_permissions p JOIN master.sys.objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name IN ($procsInClause) AND dp.name IN ('public','guest') AND p.state = 'G';"
$out = Invoke-MssqlQuery -Sql $sql
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-24" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
if ($out) {
    return New-CheckResult -Code "D-24" -Status "VULN" -Detail "레지스트리 관련 확장 저장 프로시저가 public/guest 에게 부여되어 있음" -Evidence ($out -join "`n")
} else {
    return New-CheckResult -Code "D-24" -Status "GOOD" -Detail "레지스트리 관련 확장 저장 프로시저 권한이 public/guest 에게 부여되어 있지 않음" -Evidence ""
}
