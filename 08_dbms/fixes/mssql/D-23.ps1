# D-23 (상) xp_cmdshell 사용 제한 [MSSQL] — 조치 [fix: confirm]
# checks/mssql/D-23.ps1: 취약 = xp_cmdshell 활성화 & public 실행 권한 존재. xp_cmdshell 자체를
# 끄지 않고(가이드가 제시한 둘째 조건: public 실행 권한만 제거해도 양호 기준을 충족) public
# 권한만 회수한다 - 이미 xp_cmdshell 을 정상적인 관리 작업에 쓰는 자동화가 있을 수 있어
# sysadmin 외 계정의 실행 경로만 차단하는 쪽이 더 보수적인 조치다.

Add-FixDbRollback -Sql "USE master; GRANT EXECUTE ON xp_cmdshell TO public;"
Invoke-MssqlQuery -Sql "USE master; REVOKE EXECUTE ON xp_cmdshell FROM public;" | Out-Null

$pubOut = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT dp.name FROM master.sys.database_permissions p JOIN master.sys.objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name = 'xp_cmdshell' AND dp.name = 'public' AND p.state = 'G';"
if ($pubOut) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "REVOKE 를 실행했으나 public 실행 권한이 여전히 존재함"
} else {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "xp_cmdshell 에 대한 public 실행 권한을 회수함(xp_cmdshell 자체는 비활성화하지 않음 - 다른 정상 용도 보존)"
}
$Global:FixEvidence = ""
