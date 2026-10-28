# lib/tests/win_state_snapshot.ps1 - Windows 상태 스냅샷·비교(테스트 전용, dot-source 해서 쓴다)
# run_safety_windows.ps1(진단 전후 상태 동일, S1)과 fix_safety_windows.ps1(조치 전 ↔ 원복 후 실제 상태 동일)이 함께 쓴다.
# 휘발성 러너(GitHub Actions windows-latest)에서만 쓰는 함수 정의 파일이라 자체로는 아무것도 바꾸지 않는다.
#
# 영역(키): services, registry, secpolicy, audit, firewall, shares, accounts, tasks, iis, mssql(08_dbms), temp
# 조회 실패(secedit/auditpol/sqlcmd 종료 코드·빈 결과)는 _errors 에 남긴다 - 예전에는 실패하면 빈 값끼리 "같음"이 되어
# 비교가 조용히 통과했다(S6 과 같은 원칙: 확인하지 못한 것을 같다고 하지 않는다).

# 진단(checks)이 실제로 읽는 레지스트리 키. R=하위 키까지, N=그 키의 값만(하위에 DHCP 임대 시각 등 휘발 값이 있는 키)
$Script:WinStateRegKeys = @(
    "R|HKLM:\SOFTWARE\Policies",
    "R|HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
    "R|HKLM:\SYSTEM\CurrentControlSet\Control\Lsa",
    "R|HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server",
    "R|HKLM:\SYSTEM\CurrentControlSet\Control\SecurePipeServers",
    "R|HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance",
    "R|HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers",
    "N|HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager",
    "N|HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management",
    "R|HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters",
    "R|HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters",
    "N|HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters",
    "N|HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters",
    "N|HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters",
    "R|HKLM:\SYSTEM\CurrentControlSet\Services\SNMP",
    "R|HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry",
    "R|HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security",
    "R|HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\System",
    "R|HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application",
    "R|HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon",
    "R|HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole",
    "R|HKLM:\SOFTWARE\ODBC\ODBC.INI",
    "R|HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI",
    "R|HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "R|HKLM:\SOFTWARE\Microsoft\InetStp"
)

function Get-WinStateSnapshot {
    param([string]$Category = "", [string[]]$TempExclude = @("rs_*", "fs_*"))
    $s = [ordered]@{}
    $errs = @()
    $s.services = (Get-CimInstance Win32_Service | Sort-Object Name | ForEach-Object { "$($_.Name)|$($_.StartMode)|$($_.State)" }) -join "`n"
    $lines = foreach ($spec in $Script:WinStateRegKeys) {
        $mode = $spec.Substring(0, 1); $k = $spec.Substring(2)
        if (-not (Test-Path -LiteralPath $k)) { "$k <없음>"; continue }
        $items = @(Get-Item -LiteralPath $k)
        if ($mode -eq "R") { $items += @(Get-ChildItem -LiteralPath $k -Recurse -ErrorAction SilentlyContinue) }
        foreach ($item in $items) {
            # DHCP 임대로 수시로 바뀌는 값(Tcpip\Parameters 의 Dhcp*)은 제외
            foreach ($n in ($item.GetValueNames() | Where-Object { $_ -notlike "Dhcp*" } | Sort-Object)) { "$($item.Name)|$n|$(@($item.GetValue($n)) -join ',')" }
        }
    }
    $s.registry = $lines -join "`n"
    $inf = Join-Path $env:TEMP "rs_sec_$PID.inf"
    & secedit /export /cfg $inf /quiet | Out-Null
    $secRc = $LASTEXITCODE
    $s.secpolicy = (Get-Content $inf -ErrorAction SilentlyContinue) -join "`n"; Remove-Item $inf -Force -ErrorAction SilentlyContinue
    if ($secRc -ne 0 -or $s.secpolicy -notmatch '\[System Access\]') { $errs += "secedit /export 실패(rc=$secRc)" }
    $s.audit = (& auditpol /get /category:* /r) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $s.audit) { $errs += "auditpol 조회 실패(rc=$LASTEXITCODE)" }
    # 방화벽: 프로필(켜짐·기본 동작) + 규칙(켜짐·동작·방향·프로필) + 포트/주소 필터(일괄 조회 1회씩 - 규칙마다 조회하면 수 분)
    $s.firewall = (@(Get-NetFirewallProfile | ForEach-Object { "profile|$($_.Name)|$($_.Enabled)|$($_.DefaultInboundAction)|$($_.DefaultOutboundAction)" }) +
        @(Get-NetFirewallRule | Sort-Object Name | ForEach-Object { "rule|$($_.Name)|$($_.Enabled)|$($_.Action)|$($_.Direction)|$($_.Profile)" }) +
        @(Get-NetFirewallPortFilter -All | ForEach-Object { "port|$($_.InstanceID)|$($_.Protocol)|$($_.LocalPort -join ',')|$($_.RemotePort -join ',')" } | Sort-Object) +
        @(Get-NetFirewallAddressFilter -All | ForEach-Object { "addr|$($_.InstanceID)|$($_.LocalAddress -join ',')|$($_.RemoteAddress -join ',')" } | Sort-Object)) -join "`n"
    $s.shares = (@(Get-SmbShare | ForEach-Object { "$($_.Name)|$($_.Path)" }) +
        @(Get-SmbShare | Get-SmbShareAccess | ForEach-Object { "$($_.Name)|$($_.AccountName)|$($_.AccessRight)" }) | Sort-Object) -join "`n"
    $s.accounts = ((Get-LocalUser | ForEach-Object { "$($_.Name)|$($_.Enabled)" }) +
        (Get-LocalGroupMember -SID S-1-5-32-544 | ForEach-Object { "admin|$($_.Name)" })) -join "`n"
    $s.tasks = (Get-ScheduledTask | Sort-Object TaskPath, TaskName | ForEach-Object { "$($_.TaskPath)$($_.TaskName)|$($_.State)" } |
        Where-Object { $_ -notmatch 'MicrosoftEdgeUpdate|Office|OneDrive' }) -join "`n"
    $iisFiles = @("$env:windir\System32\inetsrv\config\applicationHost.config") +
        @(Get-ChildItem "$env:SystemDrive\inetpub" -Recurse -Filter web.config -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $s.iis = ($iisFiles | Where-Object { Test-Path $_ } | ForEach-Object { "$_|$((Get-FileHash $_).Hash)" }) -join "`n"
    if ($Category -eq "08_dbms") {
        $q = "SET NOCOUNT ON; SELECT name + '|' + CAST(value_in_use AS varchar(50)) FROM sys.configurations ORDER BY name; SELECT name + '|' + CAST(is_disabled AS varchar(1)) FROM sys.server_principals WHERE type IN ('S','U','G') ORDER BY name; SELECT name FROM sys.server_audits;"
        $s.mssql = (& sqlcmd -S "(localdb)\MSSQLLocalDB" -E -C -b -h -1 -W -Q $q) -join "`n"
        if ($LASTEXITCODE -ne 0 -or -not $s.mssql) { $errs += "sqlcmd 조회 실패(rc=$LASTEXITCODE)" }
    }
    # 임시 폴더: 하위 폴더까지(깊이 4). U|=실행 계정 TEMP(진단이 쓰는 곳 - 새 파일은 실패), W|=Windows\Temp(서비스들이 수시로
    # 쓰므로 맨 위 이름만 실패 대상, 더 깊은 새 파일은 참고)
    $tl = @()
    foreach ($pair in @(@("U", $env:TEMP), @("W", "$env:windir\Temp"))) {
        foreach ($n in @(Get-ChildItem -LiteralPath $pair[1] -Recurse -Depth 4 -Name -Force -ErrorAction SilentlyContinue)) {
            $top = ($n -split '\\')[0]
            $skip = $false; foreach ($x in $TempExclude) { if ($top -like $x) { $skip = $true; break } }
            if (-not $skip) { $tl += "$($pair[0])|$n" }
        }
    }
    $s.temp = ($tl | Sort-Object) -join "`n"
    $s._errors = $errs -join "; "
    return $s
}

# 실행 상태(State)는 트리거 시작 서비스(DoSvc·lfsvc·WaaSMedicSvc 등)와 OS 예약 작업이 진단과 무관하게 바뀐다(기준선 CI 에서
# 확인) - 시작 유형·서비스/작업 추가·삭제는 항상, 실행 상태는 진단·조치 대상 서비스 목록만 실패로 본다(나머지는 참고 표시).
$Script:WinStateWatchSvc = '^(RemoteRegistry|W3SVC|WAS|FTPSVC|MSFTPSVC|SNMP|TlntSvr|TermService|WinRM|LanmanServer|MSSQL.*|SQLAgent.*|Spooler|Fax|SSDPSRV|upnphost|WerSvc|TapiSrv|SharedAccess|MpsSvc|WinDefend|Messenger|Schedule|DNS|SMTPSVC|NetTcpPortSharing)$'

function Compare-WinStateSnapshot {
    <# 반환: @{ Fail = @(문자열); Notes = @(문자열) }. -SoftAreas 에 든 영역의 차이는 Notes 로만(원복 불가로 보고된 조치 영역 등).
       -Label 은 메시지 접두어(예: "S1", "원복") #>
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After, [string[]]$SoftAreas = @(), [string[]]$SoftLinePatterns = @(), [string]$Label = "S1")
    $fail = @(); $notes = @()
    foreach ($e in @($Before._errors, $After._errors)) { if ($e) { $fail += "${Label}: 상태 조회 실패로 비교할 수 없음 - $e" } }
    foreach ($k in $Before.Keys) {
        if ($k -eq "_errors") { continue }
        $b = @($Before[$k] -split "`n" | Where-Object { $_ }); $a = @($After[$k] -split "`n" | Where-Object { $_ })
        $diff = @(Compare-Object $b $a)
        # -SoftLinePatterns 에 맞는 줄(예: 원복 불가로 보고된 이벤트 로그 크기 키)은 참고로만
        if ($SoftLinePatterns.Count -gt 0) {
            $softLines = @($diff | Where-Object { $l = $_.InputObject; @($SoftLinePatterns | Where-Object { $l -match $_ }).Count -gt 0 })
            if ($softLines.Count -gt 0) {
                $notes += "(참고, 원복 불가 보고 범위) '$k': " + (($softLines | Select-Object -First 5 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ' / ')
                $diff = @($diff | Where-Object { $softLines -notcontains $_ })
            }
        }
        if ($diff.Count -eq 0) { continue }
        $lines = @($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
        if ($k -eq "temp") {
            $new = @($diff | Where-Object SideIndicator -eq "=>" | ForEach-Object InputObject)
            $hardNew = @($new | Where-Object { $_ -like "U|*" -or ($_ -like "W|*" -and ($_ -split '\\').Count -eq 1) })
            $softNew = @($new | Where-Object { $hardNew -notcontains $_ })
            if ($SoftAreas -contains $k) { $softNew += $hardNew; $hardNew = @() }
            if ($hardNew.Count -gt 0) { $fail += "${Label}: 임시 폴더에 남은 파일: $(($hardNew | Select-Object -First 15) -join ', ')" }
            if ($softNew.Count -gt 0) { $notes += "Windows\Temp 하위의 새 파일(서비스 활동일 수 있음): $(($softNew | Select-Object -First 10) -join ', ')" }
            continue
        }
        if ($k -eq "services") {
            $mb = @{}; foreach ($l in $b) { $f = $l -split '\|'; $mb[$f[0]] = $f }
            $ma = @{}; foreach ($l in $a) { $f = $l -split '\|'; $ma[$f[0]] = $f }
            $hard = @(); $soft = @()
            foreach ($name in $mb.Keys) { if (-not $ma.ContainsKey($name)) { $hard += "사라진 서비스 $name" } }
            foreach ($name in $ma.Keys) {
                $f = $ma[$name]; $o = $mb[$name]
                if (-not $o) { $hard += "새 서비스 $($f -join '|')"; continue }
                if ($o[1] -ne $f[1]) { $hard += "$name 시작 유형 $($o[1])→$($f[1])" }
                elseif ($o[2] -ne $f[2]) {
                    # RemoteRegistry 는 Server 에서 유휴 시 스스로 멈춘다(시작 유형 그대로 Running→Stopped, main CI 40682689320 실측)
                    $idleStop = ($name -eq "RemoteRegistry" -and $o[2] -eq "Running" -and $f[2] -eq "Stopped")
                    if ($name -match $Script:WinStateWatchSvc -and -not $idleStop) { $hard += "$name $($o[2])→$($f[2])" } else { $soft += "$name $($o[2])→$($f[2])" }
                }
            }
            if ($hard.Count -gt 0) {
                if ($SoftAreas -contains $k) { $notes += "서비스 변경(원복 불가 보고 영역): $($hard -join ', ')" } else { $fail += "${Label}: 서비스 변경: $($hard -join ', ')" }
            }
            if ($soft.Count -gt 0) { $notes += "진단·조치와 무관한 서비스 실행 상태 변화(트리거 시작 등): $($soft -join ', ')" }
            continue
        }
        if ($k -eq "tasks") {
            $nb = @($b | ForEach-Object { ($_ -split '\|')[0] }); $na = @($a | ForEach-Object { ($_ -split '\|')[0] })
            $added = @(Compare-Object $nb $na | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
            if ($added.Count -gt 0) { $fail += "${Label}: 예약 작업 추가/삭제: $($added -join ', ')" }
            else { $notes += "예약 작업 실행 상태 변화(OS 작업): $($lines -join ', ')" }
            continue
        }
        $msg = "'$k' 상태가 다름`n      " + (($lines | Select-Object -First 10) -join "`n      ")
        if ($SoftAreas -contains $k) { $notes += "(참고) $msg" } else { $fail += "${Label}: $msg" }
    }
    return @{ Fail = $fail; Notes = $notes }
}
