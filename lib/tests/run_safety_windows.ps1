# lib/tests/run_safety_windows.ps1 -Category <02_windows|07_pc|03_web|08_dbms>
# Windows 계열 진단(run.ps1)의 운영 안전 실기 검사 - lib/tests/run_safety.sh(Unix)와 같은 기준.
# GitHub Actions windows-latest(휘발성 VM)에서만 실행한다(비밀값 심기·검사용 로컬 계정·IIS 풀 생성 때문). 로컬 PC 실행 금지.
#   S1 진단 전후 서비스(추가·삭제·시작 유형)·진단이 읽는 레지스트리 키·보안 정책(secedit)·감사 정책·방화벽(프로필·규칙·포트/주소
#      필터)·공유·로컬 계정·IIS 설정·예약 작업·MSSQL 설정이 같고, 임시 폴더(하위 포함)에 남긴 파일이 없음
#      (lib/tests/win_state_snapshot.ps1 - 조회 실패는 "같음"이 아니라 실패)
#   S2 비대화형으로 제한 시간 안에 끝남
#   S5 카테고리별로 "진단이 실제로 읽는 위치"에 비밀값을 심고(특수문자 포함), 결과 폴더·stdout/stderr·비관리자 결과 어디에도
#      원문(및 JSON/HTML 이스케이프 형태)이 없고, result.json 을 ConvertFrom-Json 한 문자열에도 없음.
#      양성 대조: 그 위치를 진단이 정말 읽었는지(해당 check 증적에 가려진 형태·심은 항목 이름이 나왔는지) 확인 - 읽지 않으면
#      S5 검사가 비어 있는 것이므로 실패. 결과 폴더에 Users/Everyone/Authenticated Users 권한이 없음
#   S6 비관리자 계정으로 실행한 결과를 관리자 결과와 비교 - 관리자에서 VULN 인 항목이 GOOD/NA 로 바뀌면 거짓 양호
param([Parameter(Mandatory = $true)][ValidateSet("02_windows", "07_pc", "03_web", "08_dbms")][string]$Category)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
. (Join-Path $PSScriptRoot "win_state_snapshot.ps1")
$runPs1 = Join-Path $Repo "$Category\run.ps1"
$extra = @()
if ($Category -eq "08_dbms") { $extra = @("-SqlHost", "(localdb)\MSSQLLocalDB") }
$LimitSec = 900
$fail = @(); $notes = @()

function New-SecureFromPlain([string]$Plain) {
    $ss = New-Object System.Security.SecureString
    foreach ($ch in $Plain.ToCharArray()) { $ss.AppendChar($ch) }
    return $ss
}

function Get-JsonStrings($o) {
    <# ConvertFrom-Json 결과의 모든 문자열 값(이스케이프가 풀린 상태) #>
    if ($null -eq $o) { return }
    if ($o -is [string]) { return $o }
    if ($o -is [System.Collections.IEnumerable]) { foreach ($x in $o) { Get-JsonStrings $x }; return }
    if ($o -is [System.Management.Automation.PSCustomObject]) { foreach ($pr in $o.PSObject.Properties) { Get-JsonStrings $pr.Value }; return }
    return "$o"
}

# ---- 비밀값 심기(진단 전 상태의 일부) ------------------------------------------------
# 값마다 특수문자를 섞는다(& 는 JSON 이 \u0026 으로 바꿔 원문 검색을 빠져나갈 수 있어 이스케이프 형태도 함께 검색).
$sec = [ordered]@{
    task = "Kt9!x#Q%z&T"       # 예약 작업 명령줄 --password  → W-37 이 읽음(Protect-SecretText)
    run  = "Kr7@y^P~w&R"       # HKLM Run 시작 프로그램 --password → W-62 가 읽음(Protect-SecretText)
    auto = "Ka5!Auto#Logon"    # Winlogon DefaultPassword - W-52/PC-12 는 AutoAdminLogon 만 읽음(같은 키, 음성 검사)
}
if ($Category -eq "02_windows") { $sec.snmp = "Ks3#Snmp!Comm" }          # SNMP community(값 이름) → W-29/30(서비스 구동 시)
if ($Category -eq "03_web") { $sec.pool = "Kp8!Pool#&Zx"; $sec.vdir = "Kv6!Vdir%&Q" }   # 앱 풀 processModel·vdir 자격 증명
if ($Category -eq "08_dbms") { $sec.dsn = "Kd4!Dsn#PWD"; $sec.sql = "Kq2!Sql#&Pw9" }   # ODBC DSN PWD, SQL 인증 비밀번호(DB_PASSWORD)
$controls = @()   # 양성 대조: @{ Code; Pattern(증적/상세 정규식); Why }

$wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$origDefPw = (Get-ItemProperty -Path $wl -Name DefaultPassword -ErrorAction SilentlyContinue).DefaultPassword
$origAuto = (Get-ItemProperty -Path $wl -Name AutoAdminLogon -ErrorAction SilentlyContinue).AutoAdminLogon
Set-ItemProperty -Path $wl -Name DefaultPassword -Value $sec.auto -Type String
$runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$taskName = "kisa-rs-secret"
$snmpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities"
$snmpRootExisted = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP"
$snmpInstalled = $false; $snmpStarted = $false
$iisRoot = Join-Path $env:SystemDrive "kisa_rs_iis"
$dsnRoot = "HKLM:\SOFTWARE\ODBC\ODBC.INI"
$sqlLogin = "kisa_rs"

try {
    # 공통: 예약 작업·시작 프로그램 명령줄의 비밀번호(02 는 W-37/W-62 가 읽고, 나머지 카테고리는 음성 검사)
    $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c echo backup --password $($sec.task)"
    Register-ScheduledTask -TaskName $taskName -Action $act -User "SYSTEM" -Force | Out-Null
    Set-ItemProperty -Path $runKey -Name "kisa-rs-run" -Value "cmd.exe /c echo startup --password $($sec.run)" -Type String
    # AutoAdminLogon=1: W-52/PC-12 가 Winlogon 키를 읽어 VULN 경로로 가게 한다(그 키의 DefaultPassword 가 새지 않는지)
    Set-ItemProperty -Path $wl -Name AutoAdminLogon -Value "1" -Type String

    if ($Category -eq "02_windows") {
        $controls += @{ Code = "W-37"; Pattern = 'kisa-rs-secret.*--password \*\*\*'; Why = "예약 작업 명령줄 비밀번호가 가려진 형태로 증적에 있어야 함" }
        $controls += @{ Code = "W-62"; Pattern = '--password \*\*\*'; Why = "시작 프로그램(HKLM Run) 명령줄 비밀번호가 가려진 형태로 증적에 있어야 함" }
        $controls += @{ Code = "W-52"; Pattern = 'AutoAdminLogon=1'; Why = "Winlogon 키를 읽었어야 함" }
        # SNMP: 서비스가 구동 중이어야 W-29/30 이 community 를 읽는다. 기능 설치를 시도하고(최대 5분) 실패하면 참고로만 남긴다.
        if (-not (Get-Service -Name SNMP -ErrorAction SilentlyContinue) -and (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) {
            $job = Start-Job { Install-WindowsFeature SNMP-Service -ErrorAction Stop | Out-Null }
            if (Wait-Job $job -Timeout 300) {
                try { Receive-Job $job -ErrorAction Stop | Out-Null; $snmpInstalled = $true } catch { $notes += "SNMP 기능 설치 실패: $($_.Exception.Message)" }
            } else { Stop-Job $job; $notes += "SNMP 기능 설치가 5분 안에 끝나지 않음" }
            Remove-Job $job -Force
        }
        if (-not (Test-Path $snmpKey)) { New-Item -Path $snmpKey -Force | Out-Null }
        Set-ItemProperty -Path $snmpKey -Name $sec.snmp -Value 4 -Type DWord
        $snmpSvc = Get-Service -Name SNMP -ErrorAction SilentlyContinue
        if ($snmpSvc -and $snmpSvc.Status -ne "Running") {
            try { Start-Service -Name SNMP -ErrorAction Stop; $snmpStarted = $true } catch { $notes += "SNMP 서비스 시작 실패: $($_.Exception.Message)" }
        }
        if ((Get-Service -Name SNMP -ErrorAction SilentlyContinue).Status -eq "Running") {
            $controls += @{ Code = "W-29"; Pattern = 'Community String 설정과 함께'; Why = "SNMP 구동 중 community 를 읽었어야 함" }
        } else { $notes += "SNMP 서비스를 구동하지 못해 community 비밀값은 음성 검사만(W-29/30 은 서비스 중지면 바로 GOOD)" }
    }
    if ($Category -eq "07_pc") {
        $controls += @{ Code = "PC-12"; Pattern = 'AutoAdminLogon=1'; Why = "Winlogon 키를 읽었어야 함" }
        $notes += "07_pc 진단에는 비밀값이 들어 있는 위치를 읽는 항목이 없음 - Winlogon(PC-12)만 양성 대조, 나머지는 음성 검사"
    }
    if ($Category -eq "03_web") {
        # 앱 풀(SpecificUser, 실제 로컬 계정) + 그 풀을 쓰는 하위 application + 자격 증명을 가진 virtual directory
        Import-Module WebAdministration
        foreach ($d in @("app", "vdir")) { New-Item -ItemType Directory -Force -Path (Join-Path $iisRoot $d) | Out-Null }
        $poolUser = "kisa_rs_pool"
        if (-not (Get-LocalUser -Name $poolUser -ErrorAction SilentlyContinue)) { New-LocalUser -Name $poolUser -Password (New-SecureFromPlain $sec.pool) -PasswordNeverExpires | Out-Null }
        if (-not (Test-Path "IIS:\AppPools\kisa_rs_pool")) { New-WebAppPool -Name "kisa_rs_pool" | Out-Null }
        Set-ItemProperty "IIS:\AppPools\kisa_rs_pool" -Name processModel -Value @{ userName = "$env:COMPUTERNAME\$poolUser"; password = $sec.pool; identityType = "SpecificUser" }
        New-WebApplication -Site "Default Web Site" -Name "kisa_rs_app" -PhysicalPath (Join-Path $iisRoot "app") -ApplicationPool "kisa_rs_pool" -Force | Out-Null
        New-WebVirtualDirectory -Site "Default Web Site" -Name "kisa_rs_vdir" -PhysicalPath (Join-Path $iisRoot "vdir") -Force | Out-Null
        $vf = "system.applicationHost/sites/site[@name='Default Web Site']/application[@path='/']/virtualDirectory[@path='/kisa_rs_vdir']"
        Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter $vf -Name userName -Value "kisa_rs_vdiruser"
        Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter $vf -Name password -Value $sec.vdir
        $controls += @{ Code = "WEB-09"; Pattern = 'kisa_rs_pool'; Why = "SpecificUser 앱 풀(processModel)을 읽었어야 함" }
        $controls += @{ Code = "WEB-04"; Pattern = 'kisa_rs_vdir'; Why = "자격 증명이 있는 virtual directory 를 열거했어야 함" }
    }
    if ($Category -eq "08_dbms") {
        # ODBC 시스템 DSN(PWD 포함) - D-13 이 DSN 목록을 읽는다
        New-Item -Path "$dsnRoot\ODBC Data Sources" -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path "$dsnRoot\ODBC Data Sources" -Name "KisaRsDsn" -Value "SQL Server" -Type String
        New-Item -Path "$dsnRoot\KisaRsDsn" -Force | Out-Null
        Set-ItemProperty -Path "$dsnRoot\KisaRsDsn" -Name "Server" -Value "(localdb)\MSSQLLocalDB" -Type String
        Set-ItemProperty -Path "$dsnRoot\KisaRsDsn" -Name "PWD" -Value $sec.dsn -Type String
        $controls += @{ Code = "D-13"; Pattern = 'KisaRsDsn'; Why = "비밀번호가 든 ODBC DSN 을 열거했어야 함" }
        # SQL 인증 로그인(두 번째 실행에서 DB_PASSWORD 로 넘긴다 - 진단이 실제로 쓰는 비밀값)
        & sqlcmd -S "(localdb)\MSSQLLocalDB" -E -C -b -Q "IF SUSER_ID('$sqlLogin') IS NULL CREATE LOGIN [$sqlLogin] WITH PASSWORD = '$($sec.sql)', CHECK_POLICY = OFF; ALTER SERVER ROLE sysadmin ADD MEMBER [$sqlLogin];" | Out-Null
        if ($LASTEXITCODE -ne 0) { $fail += "S5 준비: SQL 로그인 생성 실패(rc=$LASTEXITCODE)" }
    }

    $secrets = @($sec.Values)

    # ---- 관리자 실행(S1/S2) ----------------------------------------------------------------
    $before = Get-WinStateSnapshot -Category $Category
    $out = Join-Path $env:TEMP "rs_${Category}_admin"
    Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    $emptyIn = Join-Path $env:TEMP "rs_empty_stdin.txt"; Set-Content -Path $emptyIn -Value "" -NoNewline
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process powershell -ArgumentList (@("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", "`"$runPs1`"", "-OutBase", "`"$out`"") + $extra) `
        -NoNewWindow -PassThru -RedirectStandardOutput "$out.stdout.txt" -RedirectStandardError "$out.stderr.txt" -RedirectStandardInput $emptyIn
    if (-not $p.WaitForExit($LimitSec * 1000)) { $p.Kill(); $fail += "S2: 진단이 ${LimitSec}초 안에 끝나지 않음" }
    $sw.Stop()
    $after = Get-WinStateSnapshot -Category $Category
    $cmp = Compare-WinStateSnapshot -Before $before -After $after -Label "S1"
    $fail += $cmp.Fail; $notes += $cmp.Notes

    # ---- S5 검색 대상: 결과 폴더 전체 + stdout/stderr (+ 아래 SQL 인증 실행·비관리자 실행) ---------------
    $scan = @()   # @{ Dir; Files; Json }
    $resultPath = Get-ChildItem -Path $out -Recurse -Filter result.json -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    $scan += @{ Tag = "관리자"; Dir = $(if ($resultPath) { Split-Path $resultPath } else { $null }); Files = @("$out.stdout.txt", "$out.stderr.txt"); Json = $resultPath }

    if ($Category -eq "08_dbms") {
        $sqlOut = Join-Path $env:TEMP "rs_${Category}_sqlauth"
        Remove-Item -Recurse -Force $sqlOut -ErrorAction SilentlyContinue
        $env:DB_PASSWORD = $sec.sql
        try {
            $p2 = Start-Process powershell -ArgumentList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", "`"$runPs1`"", "-OutBase", "`"$sqlOut`"", "-SqlHost", "(localdb)\MSSQLLocalDB", "-SqlUser", $sqlLogin) `
                -NoNewWindow -PassThru -RedirectStandardOutput "$sqlOut.stdout.txt" -RedirectStandardError "$sqlOut.stderr.txt" -RedirectStandardInput $emptyIn
            if (-not $p2.WaitForExit($LimitSec * 1000)) { $p2.Kill(); $fail += "S2: SQL 인증 진단이 ${LimitSec}초 안에 끝나지 않음" }
        } finally { Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue }
        $sqlRes = Get-ChildItem -Path $sqlOut -Recurse -Filter result.json -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if (-not $sqlRes) { $fail += "S5: SQL 인증 진단 결과(result.json)가 없음" }
        else {
            $d01 = (Get-Content -Raw -Encoding UTF8 $sqlRes | ConvertFrom-Json).items | Where-Object code -eq "D-01" | Select-Object -First 1
            # 양성 대조: SQL 인증으로 실제 접속했어야 비밀번호를 "쓴" 실행이다
            if (-not $d01 -or $d01.status -eq "ERROR") { $fail += "S5 양성 대조 실패: SQL 인증(DB_PASSWORD) 접속이 되지 않아 비밀번호를 쓴 경로를 검사하지 못함($(if ($d01) { $d01.detail }))" }
        }
        $scan += @{ Tag = "SQL 인증"; Dir = $(if ($sqlRes) { Split-Path $sqlRes } else { $null }); Files = @("$sqlOut.stdout.txt", "$sqlOut.stderr.txt"); Json = $sqlRes }
    }

    if (-not $resultPath) {
        $fail += "진단 결과(result.json)가 없음: $((Get-Content "$out.stderr.txt" -ErrorAction SilentlyContinue | Select-Object -Last 5) -join ' / ')"
    } else {
        $runDir = Split-Path $resultPath
        $adminItems = (Get-Content -Raw -Encoding UTF8 $resultPath | ConvertFrom-Json).items
        $admin = @{}; foreach ($it in $adminItems) { $admin[$it.code] = $it.status }
        foreach ($c in $controls) {
            $it = $adminItems | Where-Object code -eq $c.Code | Select-Object -First 1
            if (-not $it -or "$($it.evidence)`n$($it.detail)" -notmatch $c.Pattern) {
                $fail += "S5 양성 대조 실패: $($c.Code) - $($c.Why)(패턴 '$($c.Pattern)'). 비밀값을 심은 위치를 진단이 읽지 않아 S5 검사가 비어 있음. 실제: $(if ($it) { "$($it.status) / $($it.detail)" } else { '항목 없음' })"
            }
        }
        $badSids = @("S-1-1-0", "S-1-5-32-545", "S-1-5-11")
        $aces = foreach ($ace in ((Get-Acl $runDir).Access | Where-Object { $_.AccessControlType -eq "Allow" })) {
            try { $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { "$($ace.IdentityReference)" } }
        $open = @($aces | Where-Object { $badSids -contains $_ })
        if ($open.Count -gt 0) { $fail += "S5: 결과 폴더에 일반 사용자 그룹 권한: $($open -join ', ')" }

        # ---- 비관리자 실행(S6) - LocalDB 는 사용자별 인스턴스라 08_dbms 는 제외 ----------------------------
        if ($Category -ne "08_dbms") {
            $nrUser = "kisa_nr"; $nrPw = "Nr!" + [guid]::NewGuid().ToString("N").Substring(0, 16)
            $nrRoot = "C:\kisa_nr"
            Remove-Item -Recurse -Force $nrRoot -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $nrRoot | Out-Null
            Copy-Item -Recurse -Path (Join-Path $Repo "lib"), (Join-Path $Repo $Category) -Destination $nrRoot
            if (-not (Get-LocalUser -Name $nrUser -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $nrUser -Password (New-SecureFromPlain $nrPw) -PasswordNeverExpires | Out-Null
            } else { Set-LocalUser -Name $nrUser -Password (New-SecureFromPlain $nrPw) }
            # "일괄 작업으로 로그온" 권한 기본 보유 그룹(관리 권한 없음) - 예약 작업으로 이 계정의 비대화형 실행을 하기 위함
            Add-LocalGroupMember -SID S-1-5-32-559 -Member $nrUser -ErrorAction SilentlyContinue
            & icacls $nrRoot /grant "${nrUser}:(OI)(CI)M" | Out-Null
            $nrOut = Join-Path $nrRoot "out"
            $nrAct = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$nrRoot\$Category\run.ps1`" -OutBase `"$nrOut`""
            Register-ScheduledTask -TaskName "kisa-rs-nr" -Action $nrAct -User $nrUser -Password $nrPw -RunLevel Limited -Force | Out-Null
            Start-ScheduledTask -TaskName "kisa-rs-nr"
            $deadline = (Get-Date).AddSeconds($LimitSec)
            Start-Sleep -Seconds 5
            while ((Get-ScheduledTask -TaskName "kisa-rs-nr").State -eq "Running" -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
            $nrInfo = Get-ScheduledTaskInfo -TaskName "kisa-rs-nr"
            Unregister-ScheduledTask -TaskName "kisa-rs-nr" -Confirm:$false
            $nrPath = Get-ChildItem -Path $nrOut -Recurse -Filter result.json -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            if (-not $nrPath) {
                $fail += "S6: 비관리자 실행 결과가 없음(작업 결과 코드 $($nrInfo.LastTaskResult))"
            } else {
                $scan += @{ Tag = "비관리자"; Dir = (Split-Path $nrPath); Files = @(); Json = $nrPath }
                $nr = @{}; foreach ($it in (Get-Content -Raw -Encoding UTF8 $nrPath | ConvertFrom-Json).items) { $nr[$it.code] = $it.status }
                $fg = @($admin.Keys | Where-Object { $admin[$_] -eq "VULN" -and $nr[$_] -in @("GOOD", "NA") } | Sort-Object | ForEach-Object { "$_(관리자=VULN 비관리자=$($nr[$_]))" })
                if ($fg.Count -gt 0) { $fail += "S6: 비관리자 실행에서 거짓 양호/해당없음: $($fg -join ', ')" }
                $vo = @($admin.Keys | Where-Object { $admin[$_] -in @("GOOD", "NA") -and $nr[$_] -eq "VULN" } | Sort-Object)
                if ($vo.Count -gt 0) { $notes += "비관리자에서만 VULN(확인 못 한 것을 취약으로 판정했을 수 있음): $($vo -join ', ')" }
                $notes += "비관리자 실행: " + ((@("GOOD", "VULN", "MANUAL", "ERROR", "NA") | ForEach-Object { $s = $_; "$s=$(@($nr.Values | Where-Object { $_ -eq $s }).Count)" }) -join ", ")
            }
            Remove-LocalUser -Name $nrUser -ErrorAction SilentlyContinue
        }
    }

    # ---- S5 비밀값 검색 ------------------------------------------------------------------
    # 원문 + JSON 이스케이프(PS 5.1 ConvertTo-Json 은 & < > ' 를 \u0026 등으로) + HTML 이스케이프 형태를 파일 바이트에서 찾고,
    # result.json 은 ConvertFrom-Json 으로 풀어 모든 문자열 값에서도 찾는다(이스케이프 형태가 무엇이든 잡힘).
    foreach ($sc in $scan) {
        $files = @($sc.Files | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
        if ($sc.Dir -and (Test-Path -LiteralPath $sc.Dir)) { $files += @(Get-ChildItem -LiteralPath $sc.Dir -Recurse -File | ForEach-Object FullName) }
        $jsonPlain = if ($sc.Json -and (Test-Path -LiteralPath $sc.Json)) { (Get-JsonStrings (Get-Content -Raw -Encoding UTF8 $sc.Json | ConvertFrom-Json)) -join "`n" } else { "" }
        foreach ($s in $secrets) {
            $variants = @($s, ((ConvertTo-Json $s).Trim('"')), [System.Net.WebUtility]::HtmlEncode($s)) | Sort-Object -Unique
            $hit = @()
            foreach ($v in $variants) { $hit += @($files | Select-String -SimpleMatch -Pattern $v -List | ForEach-Object Path) }
            if ($jsonPlain -and $jsonPlain.Contains($s)) { $hit += "$($sc.Json) (ConvertFrom-Json 후 문자열)" }
            $hit = @($hit | Sort-Object -Unique)
            if ($hit.Count -gt 0) { $fail += "S5: 비밀값($($sc.Tag) 실행)이 출력물에 남음: $($hit -join ', ')" }
        }
    }
} finally {
    # ---- 정리(심은 비밀값 되돌림) ------------------------------------------------------
    $ErrorActionPreference = "Continue"
    if ($null -eq $origDefPw) { Remove-ItemProperty -Path $wl -Name DefaultPassword -ErrorAction SilentlyContinue }
    else { Set-ItemProperty -Path $wl -Name DefaultPassword -Value $origDefPw }
    if ($null -eq $origAuto) { Remove-ItemProperty -Path $wl -Name AutoAdminLogon -ErrorAction SilentlyContinue }
    else { Set-ItemProperty -Path $wl -Name AutoAdminLogon -Value $origAuto }
    Remove-ItemProperty -Path $runKey -Name "kisa-rs-run" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    if ($Category -eq "02_windows") {
        if ($snmpStarted) { Stop-Service -Name SNMP -Force -ErrorAction SilentlyContinue }
        if ($snmpInstalled) { Set-Service -Name SNMP -StartupType Disabled -ErrorAction SilentlyContinue }
        if ($snmpRootExisted -or $snmpInstalled) { Remove-ItemProperty -Path $snmpKey -Name $sec.snmp -ErrorAction SilentlyContinue }
        else { Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP" -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if ($Category -eq "03_web") {
        Remove-WebApplication -Site "Default Web Site" -Name "kisa_rs_app" -ErrorAction SilentlyContinue
        Remove-WebVirtualDirectory -Site "Default Web Site" -Application "/" -Name "kisa_rs_vdir" -Force -ErrorAction SilentlyContinue
        Remove-WebAppPool -Name "kisa_rs_pool" -ErrorAction SilentlyContinue
        Remove-LocalUser -Name "kisa_rs_pool" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $iisRoot -ErrorAction SilentlyContinue
    }
    if ($Category -eq "08_dbms") {
        Remove-ItemProperty -Path "$dsnRoot\ODBC Data Sources" -Name "KisaRsDsn" -ErrorAction SilentlyContinue
        Remove-Item -Path "$dsnRoot\KisaRsDsn" -Recurse -Force -ErrorAction SilentlyContinue
        & sqlcmd -S "(localdb)\MSSQLLocalDB" -E -C -Q "IF SUSER_ID('$sqlLogin') IS NOT NULL DROP LOGIN [$sqlLogin];" 2>$null | Out-Null
    }
}

$label = "$Category/run-safety (관리자 $([int]$sw.Elapsed.TotalSeconds)초)"
if ($fail.Count -gt 0) {
    Write-Host "FAIL: $label"; $fail | ForEach-Object { Write-Host "  - $_" }; $notes | ForEach-Object { Write-Host "  · $_" }
    exit 1
}
Write-Host "PASS: $label"; $notes | ForEach-Object { Write-Host "  · $_" }
