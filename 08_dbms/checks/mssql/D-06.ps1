# D-06 (중) DB 사용자 계정을 개별적으로 부여하여 사용 [MSSQL]
# 판단 기준(가이드 원문): 계정이 "공용"으로 실제 여러 사람에게 공유되는지는 쿼리만으로 확인
# 불가 - 완전 자동 판정 불가. 로그인 가능한(비활성화되지 않은) 전체 계정 목록을 증적으로 제공한다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, type_desc FROM sys.server_principals WHERE type IN ('S','U') AND is_disabled = 0 ORDER BY name;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-06" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
return New-CheckResult -Code "D-06" -Status "MANUAL" -Detail "로그인 가능한 계정 목록 - 사용자별로 개별 계정을 쓰고 있는지(공용 계정 여부) 수동 검토 필요" -Evidence ($out -join "`n")
