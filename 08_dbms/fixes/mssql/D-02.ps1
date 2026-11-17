# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용 [MSSQL] — 조치 [fix: param]
# 값: accounts=비활성화할 로그인 이름(쉼표 구분) - 진단 증적의 로그인 목록 중 퇴직자·테스트·데모 등 불필요하다고 판단한 것
# 변경: 지정 로그인 ALTER LOGIN [이름] DISABLE (삭제하지 않음 - 원복 시 ENABLE)
# 영향: 지정 로그인으로 하던 DB 접속(애플리케이션·배치)이 즉시 거부됨
# 가이드 조치 방법: 불필요 계정 삭제 또는 잠금. "불필요" 판단은 사람이 한다(진단 MANUAL) - 1.7.0 값 지정 조치로 정책 값의 로그인만 끈다.
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 이름에 ]·'·제어문자 없음·SQL/Windows 로그인(sys.server_principals type S·U)으로
# 있음·지금 활성·sa·도구가 접속에 쓰는 로그인(SUSER_SNAME())·## 로 시작하는 내장 인증서 로그인이 아님·중복 없음.

$vals = @(Get-FixParam -Key "accounts")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 D-02.accounts 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$self = "$(@(Invoke-MssqlQuery -Sql 'SET NOCOUNT ON; SELECT SUSER_SNAME();') | Select-Object -First 1)".Trim()
if (-not $Global:DbQueryOk -or -not $self) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "현재 접속 로그인을 확인하지 못해 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$errs = @(); $seen = @{}
foreach ($a in $vals) {
    if ($seen.ContainsKey($a.ToLowerInvariant())) { $errs += "${a}: 값에 두 번 나옴"; continue }
    $seen[$a.ToLowerInvariant()] = $true
    if ($a -match "[\]'\x00-\x1f]") { $errs += "${a}: 로그인 이름에 쓸 수 없는 문자(] ' 제어문자)"; continue }
    if ($a -ieq "sa" -or $a.StartsWith("##")) { $errs += "${a}: 기본 관리자·내장 로그인은 대상 아님"; continue }
    if ($a -ieq $self) { $errs += "${a}: 도구가 접속에 쓰는 로그인"; continue }
    $st = "$(@(Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT is_disabled FROM sys.server_principals WHERE type IN ('S','U') AND name = N'$a';") | Select-Object -First 1)".Trim()
    if (-not $Global:DbQueryOk) { $errs += "${a}: 로그인 조회 실패"; continue }
    if ($st -eq "1") { $errs += "${a}: 이미 비활성" } elseif ($st -ne "0") { $errs += "${a}: SQL/Windows 로그인 목록에 없음" }
}
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}
$done = @(); $failed = @()
foreach ($a in $vals) {
    Add-FixDbRollback -Sql "ALTER LOGIN [$a] ENABLE;"
    Invoke-MssqlQuery -Sql "ALTER LOGIN [$a] DISABLE;" | Out-Null
    $st = "$(@(Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT is_disabled FROM sys.server_principals WHERE name = N'$a';") | Select-Object -First 1)".Trim()
    if ($st -eq "1") { $done += $a } else { $failed += $a }
}
$Global:FixEvidence = (@(Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT name, is_disabled FROM sys.server_principals WHERE type IN ('S','U') ORDER BY name;") -join "`n")
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "로그인 비활성화 실패: $($failed -join ', ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 로그인을 비활성화함(DISABLE): $($done -join ', ')"
}
