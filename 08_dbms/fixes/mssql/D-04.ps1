# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용 [MSSQL] — 조치 [fix: param]
# 값: accounts=sysadmin 서버 역할에서 뺄 로그인 이름(쉼표 구분) - 진단 증적의 sysadmin 구성원 중 불필요한 것
# 변경: ALTER SERVER ROLE sysadmin DROP MEMBER [이름] (원복 시 ADD MEMBER)
# 영향: 지정 로그인으로 하던 서버 관리 작업(로그인·DB 생성, 서버 설정 변경, 모든 DB 접근)이 즉시 실패
# 가이드 조치 방법: 관리자 권한을 꼭 필요한 계정에만. 필요 여부는 사람이 판단한다(진단 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 이름에 ]·'·제어문자 없음·지금 sysadmin 구성원·sa·도구 접속 로그인(SUSER_SNAME())·
# NT SERVICE\·NT AUTHORITY\ 서비스 계정·## 내장 로그인이 아님·중복 없음.

$vals = @(Get-FixParam -Key "accounts")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 D-04.accounts 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$self = "$(@(Invoke-MssqlQuery -Sql 'SET NOCOUNT ON; SELECT SUSER_SNAME();') | Select-Object -First 1)".Trim()
if (-not $Global:DbQueryOk -or -not $self) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "현재 접속 로그인을 확인하지 못해 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$memberSql = "SET NOCOUNT ON; SELECT sp.name FROM sys.server_role_members rm JOIN sys.server_principals sp ON rm.member_principal_id = sp.principal_id JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id WHERE r.name = 'sysadmin';"
$members = @(Invoke-MssqlQuery -Sql $memberSql | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if (-not $Global:DbQueryOk) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "sysadmin 구성원을 조회하지 못해 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$errs = @(); $seen = @{}
foreach ($a in $vals) {
    if ($seen.ContainsKey($a.ToLowerInvariant())) { $errs += "${a}: 값에 두 번 나옴"; continue }
    $seen[$a.ToLowerInvariant()] = $true
    if ($a -match "[\]'\x00-\x1f]") { $errs += "${a}: 로그인 이름에 쓸 수 없는 문자(] ' 제어문자)"; continue }
    if ($a -ieq "sa" -or $a.StartsWith("##") -or $a -match '^NT (SERVICE|AUTHORITY)\\') { $errs += "${a}: 기본 관리자·서비스·내장 로그인은 대상 아님"; continue }
    if ($a -ieq $self) { $errs += "${a}: 도구가 접속에 쓰는 로그인"; continue }
    if (@($members | Where-Object { $_ -ieq $a }).Count -eq 0) { $errs += "${a}: sysadmin 구성원이 아님" }
}
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}
foreach ($a in $vals) {
    Add-FixDbRollback -Sql "ALTER SERVER ROLE sysadmin ADD MEMBER [$a];"
    Invoke-MssqlQuery -Sql "ALTER SERVER ROLE sysadmin DROP MEMBER [$a];" | Out-Null
}
$after = @(Invoke-MssqlQuery -Sql $memberSql | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
$left = @($vals | Where-Object { $v = $_; @($after | Where-Object { $_ -ieq $v }).Count -gt 0 })
$Global:FixEvidence = "sysadmin: $($after -join ', ')"
if ($left.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "sysadmin 구성원 제거 실패: $($left -join ', ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 로그인을 sysadmin 에서 제거함: $($vals -join ', ')"
}
