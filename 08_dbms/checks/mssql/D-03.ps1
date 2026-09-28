# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [MSSQL]
# 판단 기준(가이드 원문): "기관 정책에 맞게" 적용되었는지는 완전 자동 판정 불가. SQL 로그인의
# CHECK_POLICY/CHECK_EXPIRATION(OS 암호 정책 강제 적용 여부) 설정을 증적으로 제공한다.
# CHECK_POLICY=0(정책 미적용) 계정이 하나라도 있으면 명백한 취약으로 판단한다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, is_policy_checked, is_expiration_checked FROM sys.sql_logins;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-03" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
$noPolicy = $out | Where-Object { ($_ -split '\|')[1].Trim() -eq "0" }
if ($noPolicy) {
    return New-CheckResult -Code "D-03" -Status "VULN" -Detail "암호 정책(CHECK_POLICY)이 적용되지 않은 SQL 로그인이 존재함" -Evidence ($out -join "`n")
} else {
    return New-CheckResult -Code "D-03" -Status "MANUAL" -Detail "모든 SQL 로그인에 암호 정책은 적용됨 - 만료 기간 등 구체적 값이 기관 기준에 맞는지 수동 확인 필요" -Evidence ($out -join "`n")
}
