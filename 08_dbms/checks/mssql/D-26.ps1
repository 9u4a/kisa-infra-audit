# D-26 (상) 데이터베이스의 접근, 변경, 삭제 등의 감사 기록이 기관의 감사 기록 정책에 적합하도록 설정 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 감사 로그 저장 정책 수립·적용 / 취약 = 감사 로그 미저장·정책 미적용
# 서버 감사(Server Audit) 객체가 하나도 없거나, 있어도 활성화되어 있지 않으면 명백한 취약으로
# 본다. 감사 범위(로그인 감사 수준 등)가 기관 정책에 적합한지는 MANUAL로 안내한다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, is_state_enabled FROM sys.server_audits;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-26" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
if (-not $out) {
    return New-CheckResult -Code "D-26" -Status "VULN" -Detail "구성된 서버 감사(Server Audit)가 없음 - 감사 로그가 저장되지 않음" -Evidence ""
}
$enabled = $out | Where-Object { ($_ -split '\|')[1].Trim() -eq "1" }
if ($enabled) {
    return New-CheckResult -Code "D-26" -Status "MANUAL" -Detail "활성화된 서버 감사가 있음 - 감사 범위(로그인 감사 수준 등)가 기관 감사 정책에 맞는지 수동 확인 필요" -Evidence ($out -join "`n")
} else {
    return New-CheckResult -Code "D-26" -Status "VULN" -Detail "서버 감사가 구성되어 있으나 비활성화 상태임" -Evidence ($out -join "`n")
}
