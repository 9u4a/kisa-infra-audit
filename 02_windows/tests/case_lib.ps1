# 02_windows/tests/case_lib.ps1 - 항목별 양방향 케이스(tests/fixtures/cases/<코드>.ps1)가 쓰는 상태 설정·조회 헬퍼.
# case_runner.ps1 이 dot-source 한다. 케이스 정의의 스크립트 블록은 나중에(다른 범위에서) 실행되므로 전부 global: 로 정의한다.
# GitHub Actions windows-latest(휘발성 VM) 전용 - 실제 레지스트리·보안 정책·서비스·공유·ACL 을 바꾸는 함수들이다.
# 로컬 개발자 PC 에서 이 파일의 함수를 호출하지 말 것.

$global:CaseTmpRoot = Join-Path $env:TEMP "rs_case_tmp"
New-Item -ItemType Directory -Force -Path $global:CaseTmpRoot | Out-Null
# IIS 케이스(IIS:\ 경로, Get-Website)용 - 설치돼 있을 때만
if (Get-Module -ListAvailable -Name WebAdministration) { Import-Module WebAdministration -ErrorAction SilentlyContinue }

# ---- 레지스트리 ------------------------------------------------------------------
function global:Get-CaseReg {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path
    if ($item.GetValueNames() -notcontains $Name) { return $null }
    return $item.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function global:Set-CaseReg {
    <# $Value 가 $null 이면 값 제거. 키가 없으면 만든다(기존 키에 New-Item -Force 를 쓰면 값이 지워질 수 있어 없을 때만) #>
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    if ($null -eq $Value) {
        if (Test-Path -LiteralPath $Path) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue }
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function global:Save-CaseRegKey {
    <# 키 전체를 reg export 로 저장(SNMP 커뮤니티처럼 값 이름이 가변인 키). 반환: 복원용 객체 #>
    param([string]$Path)
    $ErrorActionPreference = "Continue"
    $native = $Path -replace '^HKLM:\\', 'HKLM\'
    $file = Join-Path $global:CaseTmpRoot ("key_" + ([guid]::NewGuid().ToString("N")) + ".reg")
    $existed = Test-Path -LiteralPath $Path
    if ($existed) {
        & reg.exe export $native $file /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "reg export 실패: $native" }
    }
    return [PSCustomObject]@{ Path = $Path; Native = $native; Existed = $existed; File = $file }
}

function global:Restore-CaseRegKey {
    param($Saved)
    $ErrorActionPreference = "Continue"
    if (Test-Path -LiteralPath $Saved.Path) { & reg.exe delete $Saved.Native /f 2>&1 | Out-Null }
    if ($Saved.Existed) {
        & reg.exe import $Saved.File 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "reg import 실패: $($Saved.Native)" }
    }
}

# ---- 보안 정책(secedit) -------------------------------------------------------------
function global:Export-CaseSecPolicy {
    <# 현재 정책을 매번 새로 내보내 섹션 해시테이블로 반환(진단 모듈의 캐시와 무관) #>
    $f = Join-Path $global:CaseTmpRoot ("exp_" + ([guid]::NewGuid().ToString("N")) + ".inf")
    & secedit.exe /export /cfg $f /quiet | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $f)) { throw "secedit /export 실패(rc=$LASTEXITCODE)" }
    $sec = @{}; $cur = $null
    foreach ($line in Get-Content -LiteralPath $f -Encoding Unicode) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') { $cur = $Matches[1]; $sec[$cur] = @{} }
        elseif ($cur -and $t -match '^([^=]+?)\s*=\s*(.*)$') { $sec[$cur][$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    return $sec
}

function global:Get-CaseSecPolicy {
    param([string]$Section, [string]$Name)
    $e = Export-CaseSecPolicy
    if ($e.ContainsKey($Section) -and $e[$Section].ContainsKey($Name)) { return $e[$Section][$Name] }
    return $null
}

function global:Invoke-CaseSecedit {
    <# secedit /configure - 호출마다 새 임시 폴더(Jet 부속 파일 포함)에 DB 를 만들고 폴더째 지운다(Set-FixSecPolicyValue 와 같은 방식).
       실패하면 /log 내용을 예외에 담는다 #>
    param([string]$Cfg, [string[]]$Areas)
    $ErrorActionPreference = "Continue"
    $dir = Join-Path $global:CaseTmpRoot ("sce_" + ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $db = Join-Path $dir "case.sdb"; $log = Join-Path $dir "case.log"
    $argList = @("/configure", "/db", $db, "/cfg", $Cfg, "/areas") + $Areas + @("/log", $log, "/quiet")
    $out = & secedit.exe @argList 2>&1 | Out-String
    $rc = $LASTEXITCODE
    $logText = if (Test-Path -LiteralPath $log) { ((Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ -match '\S' }) | Select-Object -Last 12) -join " | " } else { "" }
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    if ($rc -ne 0) { throw "secedit /configure 실패(rc=$rc): $out $logText" }
}
function global:Set-CaseSecPolicy {
    <# $Section: "System Access" / "Privilege Rights" 등, $Values: key=value 해시테이블 #>
    param([string]$Section, [hashtable]$Values)
    $f = Join-Path $global:CaseTmpRoot ("set_" + ([guid]::NewGuid().ToString("N")) + ".inf")
    $lines = @("[Unicode]", "Unicode=yes", "[$Section]")
    foreach ($k in $Values.Keys) { $lines += "$k = $($Values[$k])" }
    $lines += @("[Version]", 'signature="$CHICAGO$"', "Revision=1")
    Set-Content -LiteralPath $f -Value $lines -Encoding Unicode
    try { Invoke-CaseSecedit -Cfg $f -Areas @($(if ($Section -eq "Privilege Rights") { "USER_RIGHTS" } else { "SECURITYPOLICY" })) }
    finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

function global:ConvertTo-CasePrivSet {
    <# "*S-1-5-32-544,*S-1-5-32-545" 같은 값을 비교용 정렬 문자열로 #>
    param([string]$Raw)
    return ((@("$Raw" -split ',' | ForEach-Object { $_.Trim().TrimStart('*') } | Where-Object { $_ }) | Sort-Object) -join ',')
}

# ---- 서비스 -------------------------------------------------------------------------
function global:Get-CaseService {
    param([string]$Name)
    $s = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    return [PSCustomObject]@{ Name = $Name; StartMode = "$($s.StartMode)"; State = "$($s.State)" }
}

function global:Set-CaseService {
    <# $State: Running / Stopped / Disabled(중지 + 시작 유형 사용 안 함 - 트리거 시작 서비스가 진단 중에 다시 켜지지 않게) #>
    param([string]$Name, [ValidateSet("Running", "Stopped", "Disabled")][string]$State)
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name }
    if (-not $s) {
        if ($State -eq "Running") { throw "서비스 $Name 이 없어 시작할 수 없음" }
        return
    }
    if ($State -eq "Running") {
        if ($s.StartType -eq "Disabled") { Set-Service -Name $Name -StartupType Manual }
        if ($Name -eq "RemoteRegistry") {
            # 유휴 시 스스로 멈추는 서비스 - 진단 시점까지 구동 상태를 유지하도록(02_windows/tests/fixtures/apply.ps1 과 같은 이유)
            $p = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters"
            if (-not (Test-Path $p)) { New-Item -Path $p | Out-Null }
            Set-ItemProperty -Path $p -Name DisableIdleStop -Type DWord -Value 1
            # 이미 (트리거로) 구동 중이면 그 인스턴스는 유휴 중지가 켜진 채라 곧 멈춘다 - 다시 시작해 설정을 읽게 한다(CI run 41041494009 W-18)
            if ($s.Status -eq "Running") { Restart-Service -Name $Name -Force; return }
        }
        if ($s.Status -ne "Running") { Start-Service -Name $Name }
    } else {
        if ($s.Status -ne "Stopped") { Stop-Service -Name $Name -Force }
        if ($State -eq "Disabled") { Set-Service -Name $Name -StartupType Disabled }
    }
}

function global:Restore-CaseService {
    param($Saved)
    if (-not $Saved) { return }
    $cur = Get-CaseService -Name $Saved.Name
    if (-not $cur) { return }
    $map = @{ Auto = "Automatic"; Manual = "Manual"; Disabled = "Disabled" }
    if ($cur.StartMode -ne $Saved.StartMode -and $map.ContainsKey($Saved.StartMode)) { Set-Service -Name $Saved.Name -StartupType $map[$Saved.StartMode] }
    if ($Saved.State -eq "Running" -and $cur.State -ne "Running") { Start-Service -Name $Saved.Name }
    elseif ($Saved.State -eq "Stopped" -and $cur.State -ne "Stopped") { Stop-Service -Name $Saved.Name -Force }
}

# ---- 공유(LanmanServer) ------------------------------------------------------------
function global:Get-CaseDefaultShares {
    return @(Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -match '^[A-Za-z]\$$' -or $_.Name -eq 'ADMIN$' } | ForEach-Object { $_.Name })
}

function global:Restart-CaseLanman {
    param([switch]$NoWait)
    <# 삭제한 기본 공유(C$/ADMIN$)를 되살린다 - Server 서비스 재시작 시 AutoShareServer 기본값이면 다시 만들어진다.
       재시작에 딸려 멈춘 종속 서비스는 원래 실행 중이던 것만 다시 시작한다 #>
    $deps = @(Get-Service -Name LanmanServer -DependentServices | Where-Object { $_.Status -eq "Running" } | ForEach-Object { $_.Name })
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    $guid = Get-CaseReg $p "Guid"
    Restart-Service -Name LanmanServer -Force
    foreach ($d in $deps) { Start-Service -Name $d -ErrorAction SilentlyContinue }
    # 서비스가 시작하며 Parameters\Guid 를 새로 쓴다 - 케이스 전 값으로 되돌려 레지스트리 상태 비교가 원복을 확인할 수 있게
    if ($null -ne $guid) { Set-CaseReg $p "Guid" ([byte[]]$guid) "Binary" }
    if (-not $NoWait) { for ($i = 0; $i -lt 20 -and (Get-CaseDefaultShares).Count -eq 0; $i++) { Start-Sleep -Milliseconds 500 } }
}

# ---- 파일 ACL --------------------------------------------------------------------
function global:Test-CaseAclHasSid {
    <# 허용 ACE(상속 포함) 중 해당 SID 가 있는지 #>
    param([string]$Path, [string]$Sid)
    $acl = Get-Acl -LiteralPath $Path
    return (@($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) |
            Where-Object { $_.AccessControlType -eq "Allow" -and $_.IdentityReference.Value -eq $Sid }).Count -gt 0)
}

function global:Save-CaseAcl {
    param([string]$Path)
    return [PSCustomObject]@{ Path = $Path; Sddl = (Get-Acl -LiteralPath $Path).GetSecurityDescriptorSddlForm("Access") }
}

function global:Restore-CaseAcl {
    <# DACL 만 되돌린다(소유자는 건드리지 않음 - TrustedInstaller 소유 파일에 소유자를 다시 쓰면 권한 오류) #>
    param($Saved)
    $item = Get-Item -LiteralPath $Saved.Path -Force
    $acl = $item.GetAccessControl("Access")
    $acl.SetSecurityDescriptorSddlForm($Saved.Sddl, "Access")
    $item.SetAccessControl($acl)
}

function global:Invoke-CaseIcacls {
    param([string[]]$Arguments)
    $ErrorActionPreference = "Continue"
    $out = & icacls.exe @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "icacls $($Arguments -join ' ') 실패: $out" }
}

# ---- 로컬 계정 -------------------------------------------------------------------
function global:New-CaseLocalUser {
    param([string]$Name)
    if (Get-LocalUser -Name $Name -ErrorAction SilentlyContinue) { return }
    $pw = New-Object System.Security.SecureString; foreach ($ch in ("Kc!" + [guid]::NewGuid().ToString("N")).ToCharArray()) { $pw.AppendChar($ch) }
    New-LocalUser -Name $Name -Password $pw -AccountNeverExpires -PasswordNeverExpires -Description "kisa case" | Out-Null
}

function global:Wait-CaseAdminName {
    <# 빌트인 관리자(RID 500) 이름을 진단과 같은 WMI(Win32_UserAccount)로 읽어 기대 이름이 보이면 $true(최대 60초) #>
    param([string]$Name)
    $last = ""
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $u = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True and SID like 'S-1-5-%-500'" -ErrorAction Stop
            if ($u -and $u.Name -eq $Name) { return $true }
            $last = "WMI name=$($u.Name)"
        } catch { $last = "WMI 조회 실패: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
    }
    return $last
}

function global:Remove-CaseLocalUser {
    param([string]$Name)
    if (Get-LocalUser -Name $Name -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $Name }
}

# ---- DNS 영역(W-25 / W-32) -------------------------------------------------------
function global:Test-CaseDnsZone {
    <# 시험용 영역 존재 여부. Get-DnsServerZone 은 영역이 없을 때 -ErrorAction SilentlyContinue 와 무관하게 예외를 던진다
       (CI run 41044119214/41049411046) - 예외를 "없음"으로 본다(DNS 서비스는 상태 설정 단계에서 먼저 구동됨) #>
    try { return [bool](Get-DnsServerZone -Name 'kisa-case.test' -ErrorAction Stop) } catch { return $false }
}

# ---- 이동식이 아닌 FAT32 볼륨(W-61 / PC-07) ---------------------------------------
function global:Invoke-CaseDiskpart {
    param([string[]]$Lines)
    $ErrorActionPreference = "Continue"
    $f = Join-Path $global:CaseTmpRoot ("dp_" + ([guid]::NewGuid().ToString("N")) + ".txt")
    Set-Content -LiteralPath $f -Value $Lines -Encoding ASCII
    $out = & diskpart.exe /s $f 2>&1 | Out-String
    $rc = $LASTEXITCODE
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    if ($rc -ne 0) { throw "diskpart 실패(rc=$rc): $out" }
    return $out
}

$global:CaseVhd = Join-Path $env:SystemDrive "kisa_case\fat32.vhd"
function global:Mount-CaseFatVolume {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $global:CaseVhd) | Out-Null
    if (Test-Path -LiteralPath $global:CaseVhd) { Dismount-CaseFatVolume }
    Invoke-CaseDiskpart @("create vdisk file=""$($global:CaseVhd)"" maximum=64 type=fixed", "select vdisk file=""$($global:CaseVhd)""", "attach vdisk",
        "create partition primary", "format fs=fat32 quick label=KISACASE", "assign") | Out-Null
}

function global:Dismount-CaseFatVolume {
    if (Test-Path -LiteralPath $global:CaseVhd) {
        try { Invoke-CaseDiskpart @("select vdisk file=""$($global:CaseVhd)""", "detach vdisk") | Out-Null } catch { Write-Host "  (detach: $($_.Exception.Message))" }
        Remove-Item -LiteralPath $global:CaseVhd -Force
    }
    $letters = @(Get-CimInstance Win32_LogicalDisk | ForEach-Object { $_.DeviceID.Substring(0, 1) })
    if (@(Get-SmbShare | Where-Object { $_.Name -match '^([A-Za-z])\$$' -and $letters -notcontains $Matches[1] }).Count -gt 0) { Restart-CaseLanman }
}

function global:Get-CaseNonNtfsFixedVolumes {
    return @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.FileSystem -and $_.FileSystem -notmatch '^(NTFS|ReFS)$' } |
        ForEach-Object { "$($_.DeviceID)$($_.FileSystem)" })
}

# ---- 감사 정책(auditpol) ---------------------------------------------------------
function global:Get-CaseAuditSetting {
    <# 하위 범주 GUID 의 설정을 "Success and Failure" 등 영문 문자열로(CI 러너는 en-US). 이 헬퍼는 테스트 전용 #>
    param([string]$Guid)
    $line = @(& auditpol.exe /get /subcategory:"$Guid" /r | Where-Object { $_ -like "*$Guid*" }) | Select-Object -First 1
    if (-not $line) { return $null }
    return ($line -split ',')[4]
}

function global:Set-CaseAudit {
    param([string]$Guid, [bool]$Success, [bool]$Failure)
    $s = if ($Success) { "enable" } else { "disable" }; $f = if ($Failure) { "enable" } else { "disable" }
    & auditpol.exe /set /subcategory:"$Guid" /success:$s /failure:$f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "auditpol /set 실패: $Guid" }
}

# ---- Windows Defender 서명(W-39 / PC-13) -------------------------------------------
function global:Remove-CaseDefenderSignatures {
    $ErrorActionPreference = "Continue"
    $mp = Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe"
    $out = & $mp -RemoveDefinitions -All 2>&1 | Out-String
    # 러너 이미지의 서명이 이미 OS 기본본(오래됨)이면 지울 것이 없어 rc=2 로 끝난다(CI run 41051610037) - 판단은 Check(서명 경과일)가 한다
    if ($LASTEXITCODE -ne 0) { Write-Host "  (MpCmdRun -RemoveDefinitions rc=$($LASTEXITCODE) - $($out.Trim()))" }
}

function global:Update-CaseDefenderSignatures {
    for ($i = 1; $i -le 3; $i++) {
        try { Update-MpSignature -ErrorAction Stop; break } catch { if ($i -eq 3) { throw } ; Start-Sleep -Seconds 10 }
    }
}

# ---- 방화벽 ---------------------------------------------------------------------
function global:Get-CaseFirewallEnabled {
    return @(Get-NetFirewallProfile -PolicyStore ActiveStore | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ","
}

# ---- IIS / FTP ------------------------------------------------------------------
function global:New-CaseFtpSite {
    <# 사이트 하나(포트 2121)와 홈 디렉터리를 만든다. 익명 인증은 기본(꺼짐) #>
    param([string]$Name = "kisa_case_ftp", [int]$Port = 2121)
    Import-Module WebAdministration
    $dir = Join-Path $env:SystemDrive "kisa_case\$Name"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if (-not (Get-Website | Where-Object { $_.Name -eq $Name })) { New-WebFtpSite -Name $Name -Port $Port -PhysicalPath $dir -Force | Out-Null }
    return $dir
}

function global:Remove-CaseFtpSites {
    Import-Module WebAdministration
    foreach ($s in @(Get-Website | Where-Object { $_.Name -like "kisa_case_*" })) { Remove-Website -Name $s.Name }
    $root = Join-Path $env:SystemDrive "kisa_case"
    Get-ChildItem -LiteralPath $root -Directory -Filter "kisa_case_*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
}
