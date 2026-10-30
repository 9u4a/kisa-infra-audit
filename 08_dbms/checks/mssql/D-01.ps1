# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 기본 계정의 초기 비밀번호를 변경하거나 잠금설정한 경우
#                        취약 = 초기 비밀번호를 변경하지 않거나 잠금설정을 하지 않은 경우
# 자동화 범위: sa 계정이 비활성화(disabled)되어 있으면 양호. 활성 상태면 PWDCOMPARE 로 비어 있거나 널리 알려진
# 초기/기본값 비밀번호(설치 스크립트·예제에서 흔히 쓰는 값)인지 서버 안에서 비교해 일치하면 취약(비밀번호·해시는
# 결과에 남기지 않고 일치 여부만 본다). 일치하지 않으면 "초기 비밀번호에서 변경됐는지"는 해시만으로 증명할 수 없어
# MANUAL. password_hash 는 CONTROL SERVER(sysadmin) 권한이 있어야 보이므로 보이지 않으면 MANUAL.
# 1.4.0(커버리지 C-D01): 예전에는 VULN 경로가 없어 활성 sa + 빈 비밀번호도 MANUAL 이었다.

$weak = @('', 'sa', 'password', 'Password', 'Password1', 'admin', 'sql', 'sqlserver', '1234', '123456', '12345678')
$cmp = ($weak | ForEach-Object { "PWDCOMPARE(N'$_', password_hash) = 1" }) -join ' OR '
$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, is_disabled, CASE WHEN password_hash IS NULL THEN -1 WHEN $cmp THEN 1 ELSE 0 END FROM sys.sql_logins WHERE name = 'sa';"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-01" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
if (-not $out) {
    return New-CheckResult -Code "D-01" -Status "MANUAL" -Detail "sa 계정을 찾을 수 없음 - 수동 확인 필요"
}
$fields = ($out | Select-Object -First 1) -split '\|'
$isDisabled = $fields[1].Trim()
$weakMatch = if ($fields.Count -ge 3) { $fields[2].Trim() } else { "-1" }
$evid = "sa is_disabled=$isDisabled 기본/추측 쉬운 비밀번호 일치=$(switch ($weakMatch) { '1' { '예' } '0' { '아니오' } default { '확인 불가(password_hash 조회 권한 없음)' } })"
if ($isDisabled -eq "1") {
    return New-CheckResult -Code "D-01" -Status "GOOD" -Detail "sa 계정이 비활성화(잠금)되어 있음" -Evidence $evid
}
if ($weakMatch -eq "1") {
    return New-CheckResult -Code "D-01" -Status "VULN" -Detail "sa 계정이 활성화되어 있고 비밀번호가 비어 있거나 널리 알려진 기본값임" -Evidence $evid
}
return New-CheckResult -Code "D-01" -Status "MANUAL" -Detail "sa 계정이 활성화되어 있음 - 초기 비밀번호에서 변경되었는지 수동 확인 필요" -Evidence $evid
