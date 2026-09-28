# D-25 (상) 주기적 보안 패치 및 벤더 권고 사항 적용 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 보안 패치가 적용된 버전 / 취약 = 아닌 버전
# "안전한 버전"인지는 최신 CVE·벤더 공지와 대조해야 하므로 완전 자동 판정 불가 - 현재 버전
# 정보만 증적으로 제공한다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT @@VERSION;"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-25" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
$version = ($out -join ' ').Trim()
return New-CheckResult -Code "D-25" -Status "MANUAL" -Detail "현재 버전 확인됨 - 최신 보안 패치 적용 여부는 벤더 공지와 대조하여 수동 확인 필요" -Evidence $version
