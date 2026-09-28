# D-08 (상) 안전한 암호화 알고리즘 사용 [MSSQL]
# 판단 기준(가이드 원문): 양호 = SHA-256 이상 해시 알고리즘 사용 / 취약 = SHA-256 미만
# 가이드 원문 참고: "MSSQL 2012이상에서 사용자 계정의 비밀번호는 32bit Salt를 적용한 SHA-512
# 해시 알고리즘을 사용" - 즉 이 항목은 버전에 의해 고정 결정되며 설정으로 바꿀 수 없다.

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT SERVERPROPERTY('ProductMajorVersion'), SERVERPROPERTY('ProductVersion');"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-08" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
$fields = ($out | Select-Object -First 1) -split '\|'
$major = 0
[void][int]::TryParse($fields[0].Trim(), [ref]$major)
if ($major -ge 11) {
    return New-CheckResult -Code "D-08" -Status "GOOD" -Detail "MSSQL $($fields[1].Trim()) (2012 이상) - SHA-512 해시 알고리즘을 사용함" -Evidence ($out -join "`n")
} else {
    return New-CheckResult -Code "D-08" -Status "VULN" -Detail "MSSQL $($fields[1].Trim()) (2012 미만) - SHA-256 미만 알고리즘을 사용함" -Evidence ($out -join "`n")
}
