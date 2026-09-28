# D-23 (상) xp_cmdshell 사용 제한 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 비활성화, 또는 활성화 시 (1) public 실행 권한 없음
#                        (2) 서비스 계정에 sysadmin 미부여 를 모두 만족
#                        취약 = 활성화 & 위 조건 불충족

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT value FROM sys.configurations WHERE name = 'xp_cmdshell';"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-23" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
$value = ($out | Select-Object -First 1).Trim()
if ($value -eq "0") {
    return New-CheckResult -Code "D-23" -Status "GOOD" -Detail "xp_cmdshell이 비활성화되어 있음" -Evidence "value=$value"
}

# "USE master;" 는 sqlcmd가 "Changed database context..." 메시지를 결과에 섞어 항상 결과가
# 있는 것처럼 오판되게 만든다(D-11에서 실기 테스트로 확인한 버그) - 3-part naming 으로 회피.
$pubOut = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT dp.name FROM master.sys.database_permissions p JOIN master.sys.objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name = 'xp_cmdshell' AND dp.name = 'public' AND p.state = 'G';"
$evidence = "xp_cmdshell value=$value`npublic 실행권한: $($pubOut -join ', ')"
if ($pubOut) {
    return New-CheckResult -Code "D-23" -Status "VULN" -Detail "xp_cmdshell이 활성화되어 있고 public 에게 실행 권한이 부여되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "D-23" -Status "MANUAL" -Detail "xp_cmdshell이 활성화되어 있으나 public 실행 권한은 없음 - 서비스 계정에 sysadmin 권한이 없는지 수동 확인 필요" -Evidence $evidence
}
