# D-16 (하) Windows 인증 모드 사용 [MSSQL]
# 판단 기준(가이드 원문): 양호 = Windows 인증 모드 사용 & sa 비활성화(활성 시 강력한 암호 정책)
#                        취약 = 혼합 모드 사용 & 활성화된 sa 계정에 강력한 암호 정책 미설정

$out = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT SERVERPROPERTY('IsIntegratedSecurityOnly');"
if (-not $Global:DbQueryOk) {
    $err = if (Test-Path $Global:DbErrFile) { Get-Content -Raw $Global:DbErrFile } else { "" }
    return New-CheckResult -Code "D-16" -Status "ERROR" -Detail "MSSQL 연결/쿼리 실패: $err" -Evidence ($out -join "`n")
}
$integrated = ($out | Select-Object -First 1).Trim()
if ($integrated -eq "1") {
    return New-CheckResult -Code "D-16" -Status "GOOD" -Detail "Windows 인증 모드만 사용 중(혼합 모드 아님)" -Evidence "IsIntegratedSecurityOnly=$integrated"
}

$saOut = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT is_disabled, is_policy_checked FROM sys.sql_logins WHERE name = 'sa';"
if (-not $Global:DbQueryOk -or -not $saOut) {
    return New-CheckResult -Code "D-16" -Status "MANUAL" -Detail "혼합 인증 모드 사용 중 - sa 계정 상태를 조회하지 못해 수동 확인 필요" -Evidence "IsIntegratedSecurityOnly=$integrated"
}
$saFields = ($saOut | Select-Object -First 1) -split '\|'
$saDisabled = $saFields[0].Trim()
$saPolicy = $saFields[1].Trim()
$evidence = "IsIntegratedSecurityOnly=$integrated`nsa is_disabled=$saDisabled is_policy_checked=$saPolicy"
if ($saDisabled -eq "1") {
    return New-CheckResult -Code "D-16" -Status "GOOD" -Detail "혼합 인증 모드이나 sa 계정이 비활성화되어 있음" -Evidence $evidence
} elseif ($saPolicy -eq "1") {
    return New-CheckResult -Code "D-16" -Status "GOOD" -Detail "혼합 인증 모드이며 sa 계정이 활성화되어 있으나 강력한 암호 정책이 적용됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "D-16" -Status "VULN" -Detail "혼합 인증 모드에서 sa 계정이 활성화되어 있고 암호 정책도 미적용" -Evidence $evidence
}
