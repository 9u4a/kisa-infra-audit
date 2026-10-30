# 08_dbms/tests/fixtures/cases/mssql_cases.ps1 - MSSQL 항목별 판정 양방향 케이스 구현(cases.json 의 engine=mssql 선언과 이름으로 짝지음)
# GitHub Actions windows-latest(휘발성 VM, 러너 기본 SQL Server LocalDB)에서만 실행한다 - SQL 상태·방화벽·레지스트리를 실제로 바꾼다.
# 로컬 PC 에서 실행 금지. 형식은 lib/tests/win_case_runner.ps1 참고. 기대 판정(cases.json expect)은 guide.json 판단기준에서 정했다.

$MssqlCasePrelude = @'
$inst = '(localdb)\MSSQLLocalDB'
function Sql([string]$q) {
    $ErrorActionPreference = 'Continue'
    $o = & sqlcmd -S $inst -E -C -b -h -1 -W -s '|' -Q "SET NOCOUNT ON; $q" 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd 실패: $($o -join ' ')" }
    # 한 줄 결과도 배열로 돌려준다(PowerShell 은 원소 하나짜리 배열을 풀어 (Sql ...)[0] 이 첫 글자가 됐다 - 1차 CI 실측)
    return ,@($o | Where-Object { $_ -and $_ -notmatch '^(Changed database context|Configuration option)' })
}
$caseTmp = Join-Path $env:TEMP 'kisa_mssql_case'
New-Item -ItemType Directory -Force -Path $caseTmp | Out-Null
function Get-PublicGrant([string]$Obj, [string]$Perm) {
    (Sql "SELECT COUNT(*) FROM master.sys.database_permissions p JOIN master.sys.all_objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name = '$Obj' AND dp.name = 'public' AND p.permission_name = '$Perm' AND p.state = 'G';")[0]
}
'@

$MssqlCases = @{
    # D-03 취약: 암호 정책(CHECK_POLICY)이 적용되지 않은 SQL 로그인
    "login-no-policy" = @{
        Probe = '$r = Sql "SELECT COUNT(*) FROM sys.sql_logins WHERE name = ''kisa_case_np''; SELECT ISNULL(MAX(CAST(is_policy_checked AS int)), -1) FROM sys.sql_logins WHERE name = ''kisa_case_np'';"; Write-Output ("exists=" + $r[0] + " policy=" + $r[1])'
        Setup = 'Sql ("CREATE LOGIN kisa_case_np WITH PASSWORD = N''" + [guid]::NewGuid().ToString() + "Aa1!'', CHECK_POLICY = OFF;") | Out-Null'
        Cleanup = 'Sql "IF SUSER_ID(''kisa_case_np'') IS NOT NULL DROP LOGIN kisa_case_np;" | Out-Null'
        Want = '^exists=1 policy=0$'; Fix = $true; FixExpect = @("MANUAL")
        Note = "조치 후 정책 값 적합성은 기관 판단이라 MANUAL(guide automation=partial)"
    }
    # D-10 취약: 모든 Windows 방화벽 프로필 비활성(원격 접속 제한 없음)
    "firewall-all-off" = @{
        Probe = 'Write-Output ((Get-NetFirewallProfile | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join " ")'
        Setup = '@(Get-NetFirewallProfile | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Enabled = "$($_.Enabled)" } }) | ConvertTo-Json | Set-Content -Path (Join-Path $caseTmp "fw.json") -Encoding UTF8; Set-NetFirewallProfile -All -Enabled False'
        Cleanup = '$f = Join-Path $caseTmp "fw.json"; if (Test-Path $f) { foreach ($p in (Get-Content -Raw $f | ConvertFrom-Json)) { Set-NetFirewallProfile -Name $p.Name -Enabled $p.Enabled }; Remove-Item $f }'
        Want = '^Domain=False Private=False Public=False$'; Fix = $true; FixExpect = @("MANUAL")
        Note = "방화벽을 켠 뒤 허용 IP 범위 적합성은 수동 확인(MANUAL) - 양호 방향은 자동 판정 대상 아님"
    }
    # D-11 취약: public 에 master 의 시스템(ms_shipped) 테이블 SELECT 권한
    "public-system-table" = @{
        Probe = 'Write-Output ("public_select_MSreplication_options=" + (Sql "SELECT COUNT(*) FROM master.sys.database_permissions p JOIN master.sys.objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name = ''MSreplication_options'' AND dp.name = ''public'' AND p.state = ''G'';")[0])'
        Setup = 'Sql "USE master; GRANT SELECT ON dbo.MSreplication_options TO public;" | Out-Null'
        Cleanup = 'Sql "USE master; REVOKE SELECT ON dbo.MSreplication_options FROM public;" | Out-Null'
        Want = '^public_select_MSreplication_options=1$'; Fix = $true
    }
    # D-13 수동: 시스템 ODBC 데이터 소스가 등록돼 있음(필요성은 업무 판단 - manual-by-design)
    "odbc-system-dsn" = @{
        Probe = '$k = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"; $v = if (Test-Path $k) { (Get-ItemProperty $k -ErrorAction SilentlyContinue).KisaCaseDsn } else { $null }; Write-Output ("dsn=" + [bool]$v + " keyExists=" + (Test-Path $k))'
        Setup = '$k = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"; Set-Content -Path (Join-Path $caseTmp "odbc_key.txt") -Value (Test-Path $k); if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; New-ItemProperty -Path $k -Name KisaCaseDsn -Value "SQL Server" -PropertyType String -Force | Out-Null'
        Cleanup = '$k = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"; $had = (Get-Content -Path (Join-Path $caseTmp "odbc_key.txt") -ErrorAction SilentlyContinue) -eq "True"; Remove-ItemProperty -Path $k -Name KisaCaseDsn -ErrorAction SilentlyContinue; if (-not $had -and (Test-Path $k)) { Remove-Item -Path $k -Force }'
        Want = '^dsn=True'
    }
    # D-16 취약: 혼합 인증 모드 + sa 활성 + 암호 정책 미적용(LocalDB 는 혼합 모드)
    "sa-enabled-no-policy" = @{
        Probe = 'Write-Output ("integratedOnly=" + (Sql "SELECT SERVERPROPERTY(''IsIntegratedSecurityOnly'')")[0] + " sa=" + (Sql "SELECT CONCAT(is_disabled, ''/'', is_policy_checked) FROM sys.sql_logins WHERE name = ''sa''")[0])'
        Setup = '$h = (Sql "SELECT CONVERT(varchar(max), password_hash, 1) FROM sys.sql_logins WHERE name = ''sa''")[0]; $s = (Sql "SELECT CONCAT(is_disabled, ''/'', is_policy_checked, ''/'', is_expiration_checked) FROM sys.sql_logins WHERE name = ''sa''")[0]; Set-Content -Path (Join-Path $caseTmp "sa.txt") -Value "$h`n$s"; Sql "ALTER LOGIN sa WITH CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF; ALTER LOGIN sa ENABLE;" | Out-Null'
        Cleanup = '$f = Join-Path $caseTmp "sa.txt"; if (Test-Path $f) { $l = Get-Content $f; $st = $l[1] -split "/"; Sql ("ALTER LOGIN sa WITH PASSWORD = " + $l[0] + " HASHED; ALTER LOGIN sa WITH CHECK_POLICY = " + $(if ($st[1] -eq "1") { "ON" } else { "OFF" }) + "; ALTER LOGIN sa WITH CHECK_EXPIRATION = " + $(if ($st[2] -eq "1") { "ON" } else { "OFF" }) + "; ALTER LOGIN sa " + $(if ($st[0] -eq "1") { "DISABLE" } else { "ENABLE" }) + ";") | Out-Null; Remove-Item $f }'
        Want = '^integratedOnly=0 sa=0/0$'; Fix = $true
    }
    # D-23 취약: xp_cmdshell 활성 + public 실행 권한
    "xp-cmdshell-public" = @{
        Probe = 'Write-Output ("xp_cmdshell=" + (Sql "SELECT value_in_use FROM sys.configurations WHERE name = ''xp_cmdshell''")[0] + " public_exec=" + (Get-PublicGrant "xp_cmdshell" "EXECUTE"))'
        Setup = 'Set-Content -Path (Join-Path $caseTmp "adv.txt") -Value (Sql "SELECT value_in_use FROM sys.configurations WHERE name = ''show advanced options''")[0]; Sql "EXEC sp_configure ''show advanced options'', 1; RECONFIGURE; EXEC sp_configure ''xp_cmdshell'', 1; RECONFIGURE; USE master; GRANT EXECUTE ON xp_cmdshell TO public;" | Out-Null'
        Cleanup = '$adv = (Get-Content -Path (Join-Path $caseTmp "adv.txt") -ErrorAction SilentlyContinue | Select-Object -First 1); if (-not $adv) { $adv = "0" }; Sql ("USE master; REVOKE EXECUTE ON xp_cmdshell FROM public; EXEC sp_configure ''xp_cmdshell'', 0; RECONFIGURE; EXEC sp_configure ''show advanced options'', " + $adv + "; RECONFIGURE;") | Out-Null'
        Want = '^xp_cmdshell=1 public_exec=1$'; Fix = $true; FixExpect = @("MANUAL")
        Note = "조치는 public 권한만 회수(xp_cmdshell 유지) - 서비스 계정 sysadmin 여부는 수동 확인이라 MANUAL"
    }
    # D-23 수동: xp_cmdshell 활성, public 권한 없음 - 서비스 계정 sysadmin 여부는 수동 확인
    "xp-cmdshell-enabled-only" = @{
        Probe = 'Write-Output ("xp_cmdshell=" + (Sql "SELECT value_in_use FROM sys.configurations WHERE name = ''xp_cmdshell''")[0] + " public_exec=" + (Get-PublicGrant "xp_cmdshell" "EXECUTE"))'
        Setup = 'Set-Content -Path (Join-Path $caseTmp "adv.txt") -Value (Sql "SELECT value_in_use FROM sys.configurations WHERE name = ''show advanced options''")[0]; Sql "EXEC sp_configure ''show advanced options'', 1; RECONFIGURE; EXEC sp_configure ''xp_cmdshell'', 1; RECONFIGURE;" | Out-Null'
        Cleanup = '$adv = (Get-Content -Path (Join-Path $caseTmp "adv.txt") -ErrorAction SilentlyContinue | Select-Object -First 1); if (-not $adv) { $adv = "0" }; Sql ("EXEC sp_configure ''xp_cmdshell'', 0; RECONFIGURE; EXEC sp_configure ''show advanced options'', " + $adv + "; RECONFIGURE;") | Out-Null'
        Want = '^xp_cmdshell=1 public_exec=0$'
    }
    # D-24 취약: 레지스트리 확장 저장 프로시저(xp_regwrite)에 public 실행 권한
    "xp-regwrite-public" = @{
        Probe = 'Write-Output ("public_exec_xp_regwrite=" + (Get-PublicGrant "xp_regwrite" "EXECUTE"))'
        Setup = 'Sql "USE master; GRANT EXECUTE ON xp_regwrite TO public;" | Out-Null'
        Cleanup = 'Sql "USE master; REVOKE EXECUTE ON xp_regwrite FROM public;" | Out-Null'
        Want = '^public_exec_xp_regwrite=1$'; Fix = $true
    }
    # D-24 양호: 레지스트리 확장 저장 프로시저 권한을 public/guest 에서 모두 회수(SQL Server 는 xp_regread 등을 public 에 기본 부여 -
    # 러너 LocalDB 실측, 그래서 전역 픽스처 기대값은 양쪽 모두 VULN). 회수한 것을 기록해 정리 때 그대로 다시 부여한다
    "registry-procs-revoked" = @{
        Probe = 'Write-Output ("public_guest_grants=" + ((Sql "SELECT CONCAT(o.name, ''>'', dp.name) FROM master.sys.database_permissions p JOIN master.sys.all_objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name IN (''xp_regread'',''xp_regwrite'',''xp_regdeletekey'',''xp_regdeletevalue'',''xp_regenumvalues'',''xp_regremovemultistring'',''xp_regaddmultistring'') AND dp.name IN (''public'',''guest'') AND p.state = ''G'' ORDER BY 1") -join ","))'
        Setup = '$g = @(Sql "SELECT CONCAT(o.name, ''|'', dp.name) FROM master.sys.database_permissions p JOIN master.sys.all_objects o ON p.major_id = o.object_id JOIN master.sys.database_principals dp ON p.grantee_principal_id = dp.principal_id WHERE o.name IN (''xp_regread'',''xp_regwrite'',''xp_regdeletekey'',''xp_regdeletevalue'',''xp_regenumvalues'',''xp_regremovemultistring'',''xp_regaddmultistring'') AND dp.name IN (''public'',''guest'') AND p.state = ''G''"); Set-Content -Path (Join-Path $caseTmp "regprocs.txt") -Value $g; foreach ($r in $g) { $x = $r -split "\|"; Sql "USE master; REVOKE EXECUTE ON $($x[0]) FROM [$($x[1])];" | Out-Null }'
        Cleanup = '$f = Join-Path $caseTmp "regprocs.txt"; if (Test-Path $f) { foreach ($r in @(Get-Content $f | Where-Object { $_ })) { $x = $r -split "\|"; Sql "USE master; GRANT EXECUTE ON $($x[0]) TO [$($x[1])];" | Out-Null }; Remove-Item $f }'
        Want = '^public_guest_grants=$'
    }
    # D-26 수동: 서버 감사 활성 - 감사 범위의 기관 정책 적합성은 수동 확인(manual-by-design)
    "audit-enabled" = @{
        Probe = 'Write-Output ("audits=" + ((Sql "SELECT CONCAT(name, '':'', is_state_enabled) FROM sys.server_audits ORDER BY name") -join ","))'
        Setup = 'Sql "CREATE SERVER AUDIT kisa_case_audit TO APPLICATION_LOG; ALTER SERVER AUDIT kisa_case_audit WITH (STATE = ON);" | Out-Null'
        Cleanup = 'Sql "IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = ''kisa_case_audit'') BEGIN ALTER SERVER AUDIT kisa_case_audit WITH (STATE = OFF); DROP SERVER AUDIT kisa_case_audit; END" | Out-Null'
        Want = 'kisa_case_audit:1'
    }
    # D-26 취약: 서버 감사가 있으나 비활성
    "audit-disabled" = @{
        Probe = 'Write-Output ("audits=" + ((Sql "SELECT CONCAT(name, '':'', is_state_enabled) FROM sys.server_audits ORDER BY name") -join ","))'
        Setup = 'Sql "CREATE SERVER AUDIT kisa_case_audit TO APPLICATION_LOG;" | Out-Null'
        Cleanup = 'Sql "IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = ''kisa_case_audit'') BEGIN ALTER SERVER AUDIT kisa_case_audit WITH (STATE = OFF); DROP SERVER AUDIT kisa_case_audit; END" | Out-Null'
        Want = '^audits=kisa_case_audit:0$'; Fix = $true; FixExpect = @("MANUAL")
        Note = "감사를 켠 뒤 범위의 기관 정책 적합성은 수동 확인(MANUAL)"
    }
}
