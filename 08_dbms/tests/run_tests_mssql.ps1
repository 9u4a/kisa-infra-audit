# 08_dbms/tests/run_tests_mssql.ps1 [-Bootstrap]
# GitHub Actions windows-latest(휘발성 Windows Server VM)에서만 실행한다 - 러너에 기본 설치된 SQL Server LocalDB 를
# 써서 MSSQL 진단(08_dbms/run.ps1, Windows PowerShell 5.1 + sqlcmd)을 실제로 돌린다.
#   ① 진단 회귀: D-01(sa 계정)을 vuln=활성 / hardened=비활성으로 명시하고 나머지는 LocalDB 기본값을 기준값으로 고정
#   ② 운영 안전: 잘못된 비밀번호로 실행해도 SQL Server 오류 로그의 "Login failed" 가 정확히 1건 늘고(항목마다 재시도
#      하지 않음 - 계정 잠금 방지), DB 조회 항목은 "사전 점검 실패" ERROR 로 남는다
param([switch]$Bootstrap)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$inst = "(localdb)\MSSQLLocalDB"

& SqlLocalDB start MSSQLLocalDB | Out-Null
function Sql([string]$q) { & sqlcmd -S $inst -E -C -b -h -1 -W -Q "SET NOCOUNT ON; $q" }
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
    if ($mode -eq "vuln") { Sql "ALTER LOGIN sa ENABLE;" | Out-Null } else { Sql "ALTER LOGIN sa DISABLE;" | Out-Null }
    $r = Invoke-Diag $mode
    $actual = @{}; foreach ($it in $r.Items) { $actual[$it.code] = $it.status }
    $expectedPath = Join-Path $ScriptDir "fixtures\expected_mssql_$mode.json"
    if ($Bootstrap) {
        $actual | ConvertTo-Json | Set-Content -Path $expectedPath -Encoding utf8
        Write-Host "BOOTSTRAP: mssql/$mode -> $expectedPath"
        $r.Items | ForEach-Object { Write-Host ("  {0,-5} {1,-7} {2}" -f $_.code, $_.status, $_.detail) }
        continue
    }
    if (-not (Test-Path $expectedPath)) { Write-Host "FAIL: mssql/$mode - $expectedPath 가 없음(-Bootstrap 필요)"; $fail = $true; continue }
    $expected = Get-Content -Raw $expectedPath | ConvertFrom-Json
    $failures = @(foreach ($p in $expected.PSObject.Properties) { if ($actual[$p.Name] -ne $p.Value) { "$($p.Name): 기대=$($p.Value) 실제=$($actual[$p.Name])" } })
    if ($failures.Count -gt 0) { Write-Host "FAIL: mssql/$mode - $($failures.Count)건 불일치"; $failures | ForEach-Object { Write-Host "  - $_" }; $fail = $true }
    else { Write-Host "PASS: mssql/$mode" }
}

# ② 운영 안전 - SQL 인증 로그인을 만들고 틀린 비밀번호로 실행한다
Sql "IF SUSER_ID('kisa_t') IS NULL CREATE LOGIN kisa_t WITH PASSWORD = 'Kisa_Right_Pw1!', CHECK_POLICY = OFF;" | Out-Null
# 로그인 실패 횟수는 오류 18456 확장 이벤트로 센다 - 오류 로그("Login failed")는 서버 감사 수준(AuditLevel)에 따라
# 남지 않을 수 있어(LocalDB 에서 실제로 0건) 시도 횟수의 증거로 쓸 수 없었다
Sql "IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'kisa_lf') DROP EVENT SESSION kisa_lf ON SERVER;
CREATE EVENT SESSION kisa_lf ON SERVER ADD EVENT sqlserver.error_reported (WHERE error_number = 18456) ADD TARGET package0.ring_buffer WITH (MAX_DISPATCH_LATENCY = 1 SECONDS);
ALTER EVENT SESSION kisa_lf ON SERVER STATE = START;" | Out-Null
function Get-LoginFailCount { [int]((Sql "SELECT COUNT(*) FROM (SELECT CAST(t.target_data AS XML) x FROM sys.dm_xe_session_targets t JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address WHERE s.name = 'kisa_lf' AND t.target_name = 'ring_buffer') d CROSS APPLY x.nodes('RingBufferTarget/event') n(e);") | Select-Object -Last 1) }
function Get-ErrorLogFailCount { [int]((Sql "CREATE TABLE #l (d datetime, p nvarchar(100), t nvarchar(max)); INSERT #l EXEC xp_readerrorlog 0, 1, N'Login failed'; SELECT COUNT(*) FROM #l;") | Select-Object -Last 1) }
# 대조군: 틀린 비밀번호로 sqlcmd 를 직접 1회 실행하면 1건으로 잡혀야 한다(측정 방법 자체의 검증)
$c0 = Get-LoginFailCount
$env:SQLCMDPASSWORD = "Wrong_Pw_9!"; & sqlcmd -S $inst -U kisa_t -C -l 5 -Q "SELECT 1" *>$null; Remove-Item Env:SQLCMDPASSWORD
Start-Sleep -Seconds 2
$c1 = Get-LoginFailCount
Write-Host "대조군(sqlcmd 직접 1회): 로그인 실패 $($c1 - $c0)건"
if (($c1 - $c0) -ne 1) { Write-Host "FAIL: mssql/safety - 측정 방법 검증 실패(대조군이 $($c1 - $c0)건)"; exit 1 }

$before = Get-LoginFailCount; $elBefore = Get-ErrorLogFailCount
$r = Invoke-Diag "wrongpw" @{ DB_PASSWORD = "Wrong_Pw_9!"; KISA_SQLUSER = "kisa_t" }
Start-Sleep -Seconds 2
$after = Get-LoginFailCount; $elAfter = Get-ErrorLogFailCount
Sql "DROP EVENT SESSION kisa_lf ON SERVER;" | Out-Null
$blocked = @($r.Items | Where-Object { $_.status -eq "ERROR" -and $_.detail -like "*사전 점검 실패*" })
Write-Host "잘못된 비밀번호: 로그인 실패 $($after - $before)건(오류 로그 기준 $($elAfter - $elBefore)건), 사전 점검으로 차단된 항목 $($blocked.Count)개, 소요 $($r.Seconds)초"
if ($blocked.Count -gt 0) { Write-Host "  예: $($blocked[0].code) $($blocked[0].detail)" }
if (($after - $before) -ne 1) { Write-Host "FAIL: mssql/safety - 로그인 실패가 $($after - $before)건(기대 1건)"; $fail = $true }
elseif ($blocked.Count -eq 0) { Write-Host "FAIL: mssql/safety - '사전 점검 실패' ERROR 항목이 없음"; $fail = $true }
else { Write-Host "PASS: mssql/safety" }

if ($fail) { exit 1 }
