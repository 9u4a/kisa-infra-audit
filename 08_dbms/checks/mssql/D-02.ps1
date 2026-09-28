# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용 [MSSQL]
# 판단 기준(가이드 원문): 불필요 계정 존재 여부는 조직의 운영 정책을 알아야 판단 가능
# - 완전 자동 판정 불가. 전체 로그인 목록을 증적으로 제공하고 수동 확인을 안내한다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, type_desc, is_disabled FROM sys.server_principals WHERE type IN ('S','U') ORDER BY name;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-02" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
return New-CheckResult -Code "D-02" -Status "MANUAL" -Detail "전체 로그인 목록을 확인하여 불필요한(퇴직자/테스트/데모) 계정이 있는지 수동 검토 필요" -Evidence ($out -join "`n")
