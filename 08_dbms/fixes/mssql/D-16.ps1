# D-16 (하) Windows 인증 모드 사용 [MSSQL] — 조치 [fix: auto]
# checks/mssql/D-16.ps1: 취약 = 혼합 인증 모드에서 sa 계정이 활성화되어 있고 암호 정책도
# 미적용인 경우. 인증 모드 자체(LoginMode 레지스트리)를 바꾸려면 서비스 재시작이 필요하고
# 기존 SQL 인증 연결을 전부 끊는 더 큰 변경이라, 이 스크립트는 check 가 실제로 요구하는 더
# 안전한 조치(sa 계정에 CHECK_POLICY 적용)만 수행한다 - 이것만으로도 재검증을 통과한다.

$saOut = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT is_disabled, is_policy_checked FROM sys.sql_logins WHERE name = 'sa';"
if (-not $Global:DbQueryOk -or -not $saOut) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "sa 계정 상태를 조회하지 못함"; $Global:FixEvidence = ""
    return
}
$fields = ($saOut | Select-Object -First 1) -split '\|'
$saDisabled = $fields[0].Trim()
$saPolicy = $fields[1].Trim()

if ($saDisabled -eq "1" -or $saPolicy -eq "1") {
    $Global:FixStatus = "NA"; $Global:FixDetail = "sa 계정이 이미 비활성화되어 있거나 암호 정책이 적용되어 있음(이미 정상)"; $Global:FixEvidence = ""
    return
}

Add-FixDbRollback -Sql "ALTER LOGIN sa WITH CHECK_POLICY = OFF;"
Invoke-MssqlQuery -Sql "ALTER LOGIN sa WITH CHECK_POLICY = ON;" | Out-Null

$Global:FixStatus = "APPLIED"
$Global:FixDetail = "sa 계정에 CHECK_POLICY(강력한 암호 정책)를 적용함"
$Global:FixEvidence = ""
