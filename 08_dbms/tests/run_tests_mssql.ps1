# 08_dbms/tests/run_tests_mssql.ps1 [-Bootstrap]
# GitHub Actions windows-latest(휘발성 Windows Server VM)에서만 실행한다 - 러너에 기본 설치된 SQL Server LocalDB 를
# 써서 MSSQL 진단(08_dbms/run.ps1, Windows PowerShell 5.1 + sqlcmd)을 실제로 돌린다.
#   ① 진단 회귀: 전역 픽스처 vuln = sa 활성 + 널리 알려진 비밀번호('password') + CHECK_POLICY=OFF(D-01/D-03/D-16 취약 -
#      빈 비밀번호는 SQL Server 가 활성화를 거부한다: Msg 15510 Cannot enable a login that has an empty password),
#      hardened = sa 비활성 + 강력한 무작위 비밀번호 + CHECK_POLICY=ON. 준비 직후 sys.sql_logins 를 다시 읽어 의도한
#      상태인지 확인한다(준비가 조용히 실패하면 FAIL - 1.3.x 의 기대값은 -Bootstrap 실측이라 "sa ENABLE → D-01 GOOD"
#      처럼 준비가 반영되지 않은 결과가 고정돼 있었다). 기대값(expected_mssql_<mode>.json)은 guide.json 판단기준으로
#      정한 값이다(도구 출력 아님). -Bootstrap 은 실제 결과와 기대값의 차이만 출력한다(파일을 덮어쓰지 않음).
#   ② 항목별 케이스(tests/fixtures/cases/cases.json 의 engine=mssql + mssql_cases.ps1): 한 항목씩 취약/양호 상태를 만들고
#      판정 → (조치 스크립트가 있으면) 조치 → 재진단 → 원복 → 상태 비교 → 정리 → 상태 비교(lib/tests/win_case_runner.ps1)
#   ③ 운영 안전: 잘못된 비밀번호로 실행해도 로그인 실패가 접속 시도 1회분만 늘고(항목마다 재시도 하지 않음 - 계정
#      잠금 방지), DB 조회 항목은 "사전 점검 실패" ERROR 로 남는다
param([switch]$Bootstrap)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$inst = "(localdb)\MSSQLLocalDB"

& SqlLocalDB start MSSQLLocalDB | Out-Null
function Sql([string]$q) { & sqlcmd -S $inst -E -C -b -h -1 -W -s "|" -Q "SET NOCOUNT ON; $q" }
Write-Host "LocalDB 버전: $((Sql 'SELECT @@VERSION') | Select-Object -First 1)"

function Invoke-Diag([string]$Tag, [hashtable]$Env = @{}) {
    $out = Join-Path $env:TEMP "dbms_mssql_$Tag"
    Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k], "Process") }
    $args2 = @("-NoProfile", "-NonInteractive", "-File", (Join-Path $RepoRoot "08_dbms\run.ps1"), "-SqlHost", $inst, "-OutBase", $out)
    if ($Env.ContainsKey("KISA_SQLUSER")) { $args2 += @("-SqlUser", $Env["KISA_SQLUSER"]) }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & powershell @args2 *>$null
    $sw.Stop()
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $null, "Process") }
    $path = Get-ChildItem -Path $out -Recurse -Filter result.json | Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { throw "$Tag 진단 결과(result.json)를 찾지 못함" }
    return @{ Items = (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json).items; Seconds = [int]$sw.Elapsed.TotalSeconds }
}

$fail = $false
foreach ($mode in @("vuln", "hardened")) {
    if ($mode -eq "vuln") {
        $steps = @("ALTER LOGIN sa WITH CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;", "ALTER LOGIN sa WITH PASSWORD = N'password';", "ALTER LOGIN sa ENABLE;")
        $want = "0|0|1"
    } else {
        $pw = "Kh!" + [guid]::NewGuid().ToString("N") + "9z"
        $steps = @("ALTER LOGIN sa WITH PASSWORD = N'$pw';", "ALTER LOGIN sa WITH CHECK_POLICY = ON;", "ALTER LOGIN sa DISABLE;")
        $want = "1|1|0"
    }
    foreach ($st in $steps) {
        $ErrorActionPreference = "Continue"; $o = Sql $st 2>&1 | ForEach-Object { "$_" }; $rc = $LASTEXITCODE; $ErrorActionPreference = "Stop"
        $now = "$((Sql "SELECT CONCAT(is_disabled, '|', is_policy_checked) FROM sys.sql_logins WHERE name = 'sa'") | Select-Object -First 1)".Trim()
        Write-Host "  sql: $(($st -replace "PASSWORD = N'[^']*'", "PASSWORD = N'***'")) → rc=$rc sa(is_disabled|policy)=$now $(@($o) -join ' ')"
    }
    # 준비 직후 실제 상태(is_disabled|is_policy_checked|약한 비밀번호 일치) - 준비가 반영되지 않았으면 판정을 보지 않고 FAIL
    $got = "$((Sql "SELECT CONCAT(is_disabled, '|', is_policy_checked, '|', PWDCOMPARE(N'password', password_hash)) FROM sys.sql_logins WHERE name = 'sa'") | Select-Object -First 1)".Trim()
    if ($got -ne $want) { Write-Host "FAIL: mssql/$mode - 픽스처 준비가 반영되지 않음(sa is_disabled|is_policy_checked|weakpw = '$got', 기대 '$want')"; $fail = $true; continue }
    Write-Host "[*] mssql/$mode 픽스처: sa $got"
    $r = Invoke-Diag $mode
    $actual = @{}; foreach ($it in $r.Items) { $actual[$it.code] = $it.status }
    $expectedPath = Join-Path $ScriptDir "fixtures\expected_mssql_$mode.json"
    if (-not (Test-Path $expectedPath)) { Write-Host "FAIL: mssql/$mode - $expectedPath 가 없음"; $fail = $true; continue }
    $expected = Get-Content -Raw $expectedPath | ConvertFrom-Json
    $failures = @(foreach ($p in $expected.PSObject.Properties) { if ($actual[$p.Name] -ne $p.Value) { "$($p.Name): 기대=$($p.Value) 실제=$($actual[$p.Name])" } })
    $failures += @($actual.Keys | Where-Object { -not $expected.PSObject.Properties[$_] } | ForEach-Object { "${_}: 기대값 없음(실제=$($actual[$_]))" })
    if ($Bootstrap) {
        # 기대값은 가이드 판단기준으로 사람이 정한다 - 여기서는 차이만 보여 주고 파일을 바꾸지 않는다
        Write-Host "BOOTSTRAP(diff only): mssql/$mode - 차이 $($failures.Count)건"
        $failures | ForEach-Object { Write-Host "  - $_" }
        $r.Items | ForEach-Object { Write-Host ("  {0,-5} {1,-7} {2}" -f $_.code, $_.status, $_.detail) }
        continue
    }
    if ($failures.Count -gt 0) { Write-Host "FAIL: mssql/$mode - $($failures.Count)건 불일치"; $failures | ForEach-Object { Write-Host "  - $_" }; $fail = $true }
    else { Write-Host "PASS: mssql/$mode" }
}

# ② 항목별 케이스 - hardened 상태에서 한 항목씩
. (Join-Path $RepoRoot "lib\tests\win_case_runner.ps1")
. (Join-Path $ScriptDir "fixtures\cases\mssql_cases.ps1")
$declared = Get-DeclaredCases -CasesJson (Join-Path $ScriptDir "fixtures\cases\cases.json") -Engine "mssql"
$fixPrelude = "`$env:DB_HOST = '$inst'; `$Global:DbErrFile = Join-Path ([System.IO.Path]::GetTempPath()) 'kisa-case-dbms-err.txt'; `$Global:DbConnFailed = `$false"
$caseFail = Invoke-CaseSuite -Declared $declared -Impl $MssqlCases -Repo $RepoRoot -Category "08_dbms" -FixSubDir "fixes\mssql" -Prelude $MssqlCasePrelude `
    -FixPrelude $fixPrelude -DiagArgs @("-SqlHost", $inst) -RollbackArgs @("-SqlHost", $inst) -Engine "mssql"
if (@($caseFail).Count -gt 0) { Write-Host "FAIL: mssql/cases"; $caseFail | ForEach-Object { Write-Host "  - $_" }; $fail = $true }
else { Write-Host "PASS: mssql/cases ($(@($declared).Count)건)" }

# ② 운영 안전 - SQL 인증 로그인을 만들고 틀린 비밀번호로 실행한다
Sql "IF SUSER_ID('kisa_t') IS NULL CREATE LOGIN kisa_t WITH PASSWORD = 'Kisa_Right_Pw1!', CHECK_POLICY = OFF;" | Out-Null
# 로그인 실패 횟수는 오류 18456 확장 이벤트로 센다 - 오류 로그("Login failed")는 서버 감사 수준(AuditLevel)에 따라
# 남지 않을 수 있어(LocalDB 에서 실제로 0건) 시도 횟수의 증거로 쓸 수 없었다
Sql "IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'kisa_lf') DROP EVENT SESSION kisa_lf ON SERVER;
CREATE EVENT SESSION kisa_lf ON SERVER ADD EVENT sqlserver.error_reported (WHERE error_number = 18456) ADD TARGET package0.ring_buffer WITH (MAX_DISPATCH_LATENCY = 1 SECONDS);
ALTER EVENT SESSION kisa_lf ON SERVER STATE = START;" | Out-Null
function Get-LoginFailCount { [int]((Sql "SELECT COUNT(*) FROM (SELECT CAST(t.target_data AS XML) x FROM sys.dm_xe_session_targets t JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address WHERE s.name = 'kisa_lf' AND t.target_name = 'ring_buffer') d CROSS APPLY x.nodes('RingBufferTarget/event') n(e);") | Select-Object -Last 1) }
function Get-ErrorLogFailCount { [int]((Sql "CREATE TABLE #l (d datetime, p nvarchar(100), t nvarchar(max)); INSERT #l EXEC xp_readerrorlog 0, 1, N'Login failed'; SELECT COUNT(*) FROM #l;") | Select-Object -Last 1) }
# 대조군: 틀린 비밀번호로 sqlcmd 를 직접 1회 실행했을 때의 건수 = "접속 시도 1회"의 단위. 러너에서는 1회에 2건이
# 잡혔다(드라이버 재시도 또는 이벤트 중복 - 어느 쪽이든 도구도 같은 sqlcmd 를 쓰므로 단위가 같다)
$c0 = Get-LoginFailCount
# (PS 5.1 은 $ErrorActionPreference=Stop 에서 네이티브 명령의 stderr 를 예외로 바꾼다 - 실패가 기대 동작이므로 이 호출만 Continue)
$env:SQLCMDPASSWORD = "Wrong_Pw_9!"
$ErrorActionPreference = "Continue"; & sqlcmd -S $inst -U kisa_t -C -l 5 -Q "SELECT 1" *>$null; $ErrorActionPreference = "Stop"
Remove-Item Env:SQLCMDPASSWORD
Start-Sleep -Seconds 2
$c1 = Get-LoginFailCount
Write-Host "대조군(sqlcmd 직접 1회): 로그인 실패 $($c1 - $c0)건"
$unit = $c1 - $c0
if ($unit -lt 1) { Write-Host "FAIL: mssql/safety - 측정 방법 검증 실패(대조군이 ${unit}건)"; exit 1 }

$before = Get-LoginFailCount; $elBefore = Get-ErrorLogFailCount
$r = Invoke-Diag "wrongpw" @{ DB_PASSWORD = "Wrong_Pw_9!"; KISA_SQLUSER = "kisa_t" }
Start-Sleep -Seconds 2
$after = Get-LoginFailCount; $elAfter = Get-ErrorLogFailCount
Sql "DROP EVENT SESSION kisa_lf ON SERVER;" | Out-Null
$blocked = @($r.Items | Where-Object { $_.status -eq "ERROR" -and $_.detail -like "*사전 점검 실패*" })
Write-Host "잘못된 비밀번호: 로그인 실패 $($after - $before)건 = 접속 시도 $(($after - $before) / $unit)회(대조군 1회=${unit}건, 오류 로그 기준 $($elAfter - $elBefore)건), 사전 점검으로 차단된 항목 $($blocked.Count)개, 소요 $($r.Seconds)초"
if ($blocked.Count -gt 0) { Write-Host "  예: $($blocked[0].code) $($blocked[0].detail)" }
if (($after - $before) -ne $unit) { Write-Host "FAIL: mssql/safety - 로그인 실패가 $($after - $before)건(기대 ${unit}건 = 접속 시도 1회)"; $fail = $true }
elseif ($blocked.Count -eq 0) { Write-Host "FAIL: mssql/safety - '사전 점검 실패' ERROR 항목이 없음"; $fail = $true }
elseif ($blocked[0].detail -match 'char:\d+|CategoryInfo') { Write-Host "FAIL: mssql/safety - detail 에 PowerShell 오류 레코드 잡음이 남음"; $fail = $true }
else { Write-Host "PASS: mssql/safety" }

if ($fail) { exit 1 }
