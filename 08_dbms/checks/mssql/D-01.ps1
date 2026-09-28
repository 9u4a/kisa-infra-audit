# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 기본 계정의 초기 비밀번호를 변경하거나 잠금설정한 경우
#                        취약 = 초기 비밀번호를 변경하지 않거나 잠금설정을 하지 않은 경우
# 자동화 범위: sa 계정이 비활성화(disabled)되어 있으면 양호. 활성 상태에서 비밀번호가 실제로
# 변경되었는지는 해시만으로 판정 불가하므로 MANUAL로 응답한다(MySQL/PostgreSQL과 달리 MSSQL은
# 설치 시 sa 비밀번호 입력이 필수라 "비어있음" 신호를 쓸 수 없음).

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, is_disabled FROM sys.sql_logins WHERE name = 'sa';"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-01" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
if (-not $out) {
    return New-CheckResult -Code "D-01" -Status "MANUAL" -Detail "sa 계정을 찾을 수 없음 - 수동 확인 필요"
}
$fields = ($out | Select-Object -First 1) -split '\|'
$isDisabled = $fields[1].Trim()
if ($isDisabled -eq "1") {
    return New-CheckResult -Code "D-01" -Status "GOOD" -Detail "sa 계정이 비활성화(잠금)되어 있음" -Evidence ($out -join "`n")
} else {
    return New-CheckResult -Code "D-01" -Status "MANUAL" -Detail "sa 계정이 활성화되어 있음 - 초기 비밀번호에서 변경되었는지 수동 확인 필요" -Evidence ($out -join "`n")
}
