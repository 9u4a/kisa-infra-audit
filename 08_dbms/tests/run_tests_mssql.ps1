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
function Get-LoginFailCount { [int]((Sql "CREATE TABLE #l (d datetime, p nvarchar(100), t nvarchar(max)); INSERT #l EXEC xp_readerrorlog 0, 1, N'Login failed'; SELECT COUNT(*) FROM #l;") | Select-Object -Last 1) }
$before = Get-LoginFailCount
$r = Invoke-Diag "wrongpw" @{ DB_PASSWORD = "Wrong_Pw_9!"; KISA_SQLUSER = "kisa_t" }
Start-Sleep -Seconds 2
$after = Get-LoginFailCount
$blocked = @($r.Items | Where-Object { $_.status -eq "ERROR" -and $_.detail -like "*사전 점검 실패*" })
Write-Host "잘못된 비밀번호: 로그인 실패 $($after - $before)건, 사전 점검으로 차단된 항목 $($blocked.Count)개, 소요 $($r.Seconds)초"
if (($after - $before) -ne 1) { Write-Host "FAIL: mssql/safety - 로그인 실패가 $($after - $before)건(기대 1건)"; $fail = $true }
elseif ($blocked.Count -eq 0) { Write-Host "FAIL: mssql/safety - '사전 점검 실패' ERROR 항목이 없음"; $fail = $true }
else { Write-Host "PASS: mssql/safety" }

if ($fail) { exit 1 }
