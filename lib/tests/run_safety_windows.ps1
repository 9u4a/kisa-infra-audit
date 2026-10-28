# lib/tests/run_safety_windows.ps1 -Category <02_windows|07_pc|03_web|08_dbms>
# Windows 계열 진단(run.ps1)의 운영 안전 실기 검사 - lib/tests/run_safety.sh(Unix)와 같은 기준.
# GitHub Actions windows-latest(휘발성 VM)에서만 실행한다(비밀값 심기·검사용 로컬 계정 생성 때문). 로컬 PC 실행 금지.
#   S1 진단 전후 서비스·레지스트리 주요 키·보안 정책(secedit)·감사 정책·방화벽·공유·로컬 계정·IIS 설정·예약 작업이 같고,
#      임시 폴더에 남긴 파일이 없음
#   S2 비대화형으로 제한 시간 안에 끝남
#   S5 심어 둔 비밀값(자동 로그온 비밀번호·SNMP community·예약 작업 명령줄 비밀번호)이 출력물 어디에도 없고,
#      결과 폴더에 Users/Everyone/Authenticated Users 권한이 없음
#   S6 비관리자 계정으로 실행한 결과를 관리자 결과와 비교 - 관리자에서 VULN 인 항목이 GOOD/NA 로 바뀌면 거짓 양호
param([Parameter(Mandatory = $true)][ValidateSet("02_windows", "07_pc", "03_web", "08_dbms")][string]$Category)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$runPs1 = Join-Path $Repo "$Category\run.ps1"
$extra = @()
if ($Category -eq "08_dbms") { $extra = @("-SqlHost", "(localdb)\MSSQLLocalDB") }
$LimitSec = 900

# ---- 비밀값 심기(진단 전 상태의 일부) ------------------------------------------------
$secrets = @("KisaAutoLogonPw77", "KisaSnmpComm88", "KisaTaskPw99")
$wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$origDefPw = (Get-ItemProperty -Path $wl -Name DefaultPassword -ErrorAction SilentlyContinue).DefaultPassword
Set-ItemProperty -Path $wl -Name DefaultPassword -Value $secrets[0] -Type String
$snmpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities"
$snmpRootExisted = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP"
if (-not (Test-Path $snmpKey)) { New-Item -Path $snmpKey -Force | Out-Null }
Set-ItemProperty -Path $snmpKey -Name $secrets[1] -Value 4 -Type DWord
$taskName = "kisa-rs-secret"
$act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c echo backup --password $($secrets[2])"
Register-ScheduledTask -TaskName $taskName -Action $act -User "SYSTEM" -Force | Out-Null

function Get-StateSnapshot {
    $s = [ordered]@{}
    $s.services = (Get-CimInstance Win32_Service | Sort-Object Name | ForEach-Object { "$($_.Name)|$($_.StartMode)|$($_.State)" }) -join "`n"
    $keys = @("HKLM:\SOFTWARE\Policies", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa", "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server",
        "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters", "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP",
        "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry", "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security",
        "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\System", "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon")
    $lines = foreach ($k in $keys) {
        if (-not (Test-Path $k)) { "$k <없음>"; continue }
        foreach ($item in @(Get-Item $k) + @(Get-ChildItem $k -Recurse -ErrorAction SilentlyContinue)) {
            foreach ($n in ($item.GetValueNames() | Sort-Object)) { "$($item.Name)|$n|$(@($item.GetValue($n)) -join ',')" }
        }
    }
    $s.registry = $lines -join "`n"
    $inf = Join-Path $env:TEMP "rs_sec_$PID.inf"
    & secedit /export /cfg $inf /quiet | Out-Null
    $s.secpolicy = (Get-Content $inf -ErrorAction SilentlyContinue) -join "`n"; Remove-Item $inf -Force -ErrorAction SilentlyContinue
    $s.audit = (& auditpol /get /category:* /r) -join "`n"
    $s.firewall = ((Get-NetFirewallProfile | ForEach-Object { "$($_.Name)|$($_.Enabled)" }) +
        (Get-NetFirewallRule | Sort-Object Name | ForEach-Object { "$($_.Name)|$($_.Enabled)|$($_.Action)" })) -join "`n"
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
        $s.mssql = (& sqlcmd -S "(localdb)\MSSQLLocalDB" -E -C -h -1 -W -Q $q) -join "`n"
    }
    $s.temp = (@(Get-ChildItem $env:TEMP -Name -ErrorAction SilentlyContinue) + @(Get-ChildItem "$env:windir\Temp" -Name -ErrorAction SilentlyContinue) |
        Where-Object { $_ -notlike "rs_*" } | Sort-Object) -join "`n"
    return $s
}

$fail = @(); $notes = @()
$before = Get-StateSnapshot
$out = Join-Path $env:TEMP "rs_${Category}_admin"
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
$emptyIn = Join-Path $env:TEMP "rs_empty_stdin.txt"; Set-Content -Path $emptyIn -Value "" -NoNewline
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process powershell -ArgumentList (@("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", "`"$runPs1`"", "-OutBase", "`"$out`"") + $extra) `
    -NoNewWindow -PassThru -RedirectStandardOutput "$out.stdout.txt" -RedirectStandardError "$out.stderr.txt" -RedirectStandardInput $emptyIn
if (-not $p.WaitForExit($LimitSec * 1000)) { $p.Kill(); $fail += "S2: 진단이 ${LimitSec}초 안에 끝나지 않음" }
$sw.Stop()
$after = Get-StateSnapshot

# 실행 상태(State)는 트리거 시작 서비스(DoSvc·lfsvc·WaaSMedicSvc 등)와 OS 예약 작업이 진단과 무관하게 바뀐다(기준선
# CI 에서 확인) - 시작 유형·작업 추가/삭제는 항상, 실행 상태는 진단 대상 서비스 목록만 실패로 본다(나머지는 참고 표시).
$watchSvc = '^(RemoteRegistry|W3SVC|WAS|FTPSVC|MSFTPSVC|SNMP|TlntSvr|TermService|WinRM|LanmanServer|MSSQL.*|SQLAgent.*|Spooler|Fax|SSDPSRV|upnphost|WerSvc|TapiSrv|SharedAccess|MpsSvc|WinDefend|Messenger|Schedule|DNS|SMTPSVC|NetTcpPortSharing)$'
foreach ($k in $before.Keys) {
    $b = @($before[$k] -split "`n" | Where-Object { $_ }); $a = @($after[$k] -split "`n" | Where-Object { $_ })
    $diff = @(Compare-Object $b $a)
    if ($diff.Count -eq 0) { continue }
    if ($k -eq "temp") {
        $new = @($diff | Where-Object SideIndicator -eq "=>" | ForEach-Object InputObject)
        if ($new.Count -gt 0) { $fail += "S1: 임시 폴더에 진단이 남긴 파일: $($new -join ', ')" }
        continue
    }
    $lines = @($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
    if ($k -eq "services") {
        $mb = @{}; foreach ($l in $b) { $f = $l -split '\|'; $mb[$f[0]] = $f }
        $hard = @(); $soft = @()
        foreach ($l in $a) {
            $f = $l -split '\|'; $o = $mb[$f[0]]
            if (-not $o) { $hard += "새 서비스 $l"; continue }
            if ($o[1] -ne $f[1]) { $hard += "$($f[0]) 시작 유형 $($o[1])→$($f[1])" }
            elseif ($o[2] -ne $f[2]) { if ($f[0] -match $watchSvc) { $hard += "$($f[0]) $($o[2])→$($f[2])" } else { $soft += "$($f[0]) $($o[2])→$($f[2])" } }
        }
        if ($hard.Count -gt 0) { $fail += "S1: 서비스 변경: $($hard -join ', ')" }
        if ($soft.Count -gt 0) { $notes += "진단과 무관한 서비스 실행 상태 변화(트리거 시작 등): $($soft -join ', ')" }
        continue
    }
    if ($k -eq "tasks") {
        $nb = @($b | ForEach-Object { ($_ -split '\|')[0] }); $na = @($a | ForEach-Object { ($_ -split '\|')[0] })
        $added = @(Compare-Object $nb $na | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
        if ($added.Count -gt 0) { $fail += "S1: 예약 작업 추가/삭제: $($added -join ', ')" }
        else { $notes += "예약 작업 실행 상태 변화(OS 작업): $($lines -join ', ')" }
        continue
    }
    $fail += "S1: 진단 전후 '$k' 상태가 다름`n      " + (($lines | Select-Object -First 10) -join "`n      ")
}

$resultPath = Get-ChildItem -Path $out -Recurse -Filter result.json -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $resultPath) {
    $fail += "진단 결과(result.json)가 없음: $((Get-Content "$out.stderr.txt" -ErrorAction SilentlyContinue | Select-Object -Last 5) -join ' / ')"
} else {
    $runDir = Split-Path $resultPath
    $admin = @{}; foreach ($it in (Get-Content -Raw -Encoding UTF8 $resultPath | ConvertFrom-Json).items) { $admin[$it.code] = $it.status }
    foreach ($sec in $secrets) {
        $hit = @(Get-ChildItem $runDir -Recurse -File | Select-String -SimpleMatch -Pattern $sec -List | ForEach-Object Path)
        if ($hit.Count -gt 0) { $fail += "S5: 비밀값 '$sec' 이 출력물에 남음: $($hit -join ', ')" }
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
        $nrSecure = New-Object System.Security.SecureString
        foreach ($ch in $nrPw.ToCharArray()) { $nrSecure.AppendChar($ch) }
        if (-not (Get-LocalUser -Name $nrUser -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $nrUser -Password $nrSecure -PasswordNeverExpires | Out-Null
        } else { Set-LocalUser -Name $nrUser -Password $nrSecure }
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

# ---- 정리(심은 비밀값 되돌림) ----------------------------------------------------------
if ($null -eq $origDefPw) { Remove-ItemProperty -Path $wl -Name DefaultPassword -ErrorAction SilentlyContinue }
else { Set-ItemProperty -Path $wl -Name DefaultPassword -Value $origDefPw }
if ($snmpRootExisted) { Remove-ItemProperty -Path $snmpKey -Name $secrets[1] -ErrorAction SilentlyContinue }
else { Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP" -Recurse -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$label = "$Category/run-safety (관리자 $([int]$sw.Elapsed.TotalSeconds)초)"
if ($fail.Count -gt 0) {
    Write-Host "FAIL: $label"; $fail | ForEach-Object { Write-Host "  - $_" }; $notes | ForEach-Object { Write-Host "  · $_" }
    exit 1
}
Write-Host "PASS: $label"; $notes | ForEach-Object { Write-Host "  · $_" }
