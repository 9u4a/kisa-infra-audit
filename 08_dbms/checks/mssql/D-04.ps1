# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용 [MSSQL]
# 판단 기준(가이드 원문): "필요한 계정에만" 부여되었는지는 조직의 업무 요구를 알아야 판단
# 가능 - 완전 자동 판정 불가. sysadmin 서버 역할 구성원 목록을 증적으로 제공한다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT sp.name FROM sys.server_role_members rm JOIN sys.server_principals sp ON rm.member_principal_id = sp.principal_id JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id WHERE r.name = 'sysadmin' ORDER BY sp.name;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-04" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
return New-CheckResult -Code "D-04" -Status "MANUAL" -Detail "sysadmin 서버 역할 구성원 목록 - 관리 업무에 실제로 필요한 계정인지 수동 검토 필요" -Evidence ($out -join "`n")
