# lib/Common.psm1 — Windows 계열(02_windows, 03_web(IIS), 07_pc, 08_dbms(MSSQL)) 공용 모듈
#
# PowerShell 5.1 호환. 대상 호스트에는 이 파일 + 카테고리 run.ps1/checks/*.ps1 만 배치하면 된다.
# 사용: 카테고리 run.ps1 에서 "Import-Module $PSScriptRoot\..\lib\Common.psm1 -Force"

# VERSION 파일이 버전의 단일 소스다 (루트 CLAUDE.md 버전 규칙 참고). $PSScriptRoot 는 이
# 모듈 파일(lib/Common.psm1)의 위치를 가리키므로 그 상위 디렉터리에서 VERSION 을 읽는다.
$_versionFile = Join-Path $PSScriptRoot "..\VERSION"
$Script:ToolVersion = if (Test-Path $_versionFile) { (Get-Content -Raw $_versionFile).Trim() } else { "0.0.0-unknown" }
$Script:GuideVersion = "2026"

$StatusLabelKo = @{
    VULN = "취약"; MANUAL = "수동점검"; ERROR = "오류"; NA = "해당없음"; GOOD = "양호"
}
$StatusColor = @{
    VULN = "Red"; MANUAL = "Yellow"; ERROR = "Magenta"; NA = "DarkGray"; GOOD = "Green"
}
$StatusOrder = @{ VULN = 0; MANUAL = 1; ERROR = 2; NA = 3; GOOD = 4 }

# 모듈 함수의 WMI/CIM 조회 시간 제한(운영 안전 기준 S2). WMI 저장소 손상·서비스 정지 시 첫 조회
# (Get-OsFamily)부터 무기한 멈출 수 있다. 모듈 범위 변수라 사용자 세션의 기본값은 건드리지 않는다.
# 각 run.ps1 도 같은 값을 스크립트 범위로 두어 checks/*.ps1 에 적용한다.
$PSDefaultParameterValues = @{ 'Get-CimInstance:OperationTimeoutSec' = 30 }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    switch ($Level) {
        "WARN"  { Write-Host "[$ts] 경고: $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "[$ts] 오류: $Message" -ForegroundColor Red }
        default { Write-Host "[$ts] $Message" }
    }
    if ($Script:RunLogPath) {
        "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Out-File -FilePath $Script:RunLogPath -Append -Encoding utf8
    }
}

function Get-OsFamily {
    <# 결과: server2012r2 | server2016 | server2019 | server2022 | win10 | win11 | unknown #>
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $caption = $os.Caption
        $build = [int]$os.BuildNumber
    } catch {
        return "unknown"
    }
    if ($caption -match "Server") {
        if ($build -ge 20348) { return "server2022" }
        if ($build -ge 17763) { return "server2019" }
        if ($build -ge 14393) { return "server2016" }
        return "server2012r2"
    } else {
        if ($build -ge 22000) { return "win11" }
        return "win10"
    }
}

function Show-Banner {
    param([string]$Category, [int]$Total, [string]$OsFamily)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host "=== 주요정보통신기반시설 자동 진단 (도구 v$($Script:ToolVersion) / 가이드 $($Script:GuideVersion)) ===" -ForegroundColor Cyan
    Write-Host "카테고리   : $Category"
    Write-Host "호스트     : $env:COMPUTERNAME"
    Write-Host "환경       : $OsFamily"
    Write-Host "실행 계정  : $env:USERNAME (Administrator: $isAdmin)"
    if (-not $isAdmin) { Write-Log "관리자 권한이 아닙니다. 일부 항목이 ERROR/MANUAL 로 표시될 수 있습니다." "WARN" }
    Write-Host "대상 항목  : $Total 개"
    Write-Host "시작 시각  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "----------------------------------------------------------------------"
}

function Show-Progress {
    param([int]$Current, [int]$Total, [string]$Code, [string]$Title, [string]$Status)
    $pct = [int](($Current * 100) / $Total)
    $filled = [int]($pct / 5)
    $bar = ("#" * $filled).PadRight(20, ".")
    $label = $StatusLabelKo[$Status]; if (-not $label) { $label = $Status }
    $color = $StatusColor[$Status]; if (-not $color) { $color = "Gray" }
    $line = "[{0,3}/{1,3}] {2,3}% [{3}] {4,-8} {5,-40} " -f $Current, $Total, $pct, $bar, $Code, $Title
    Write-Host $line -NoNewline
    Write-Host $label -ForegroundColor $color
}

# 실행자·Administrators·SYSTEM 만 접근 가능한 폴더 생성(상속 차단). 진단 증적(계정 목록·예약 작업
# 명령줄 등)과 조치 백업이 도구를 둔 공유 폴더/C:\Temp 의 상속 권한 때문에 일반 사용자에게 읽히지
# 않게 한다. Linux(pwsh 7, MSSQL 호스트)에서는 chmod 700.
function New-PrivateDirectory {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    try {
        if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') {
            & chmod 700 $Path
            if ($LASTEXITCODE -ne 0) { throw "chmod 700 실패(exit=$LASTEXITCODE)" }
            return
        }
        $di = Get-Item -LiteralPath $Path
        $acl = $di.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($r in @($acl.Access)) { $null = $acl.RemoveAccessRule($r) }
        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
        $sids = @(
            (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')),
            (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')),
            [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        )
        foreach ($sid in $sids) {
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $sid, 'FullControl', $inherit, [System.Security.AccessControl.PropagationFlags]::None, 'Allow')))
        }
        $di.SetAccessControl($acl)
    } catch {
        # R-12: 예전에는 경고만 하고 진행해, 상속 권한(공유 폴더·C:\Temp 등)으로 남이 읽을 수 있는 폴더에 계정 목록·
        # 정책·백업이 그대로 쌓였다. 권한을 제한하지 못하면 중단한다(호출자: 진단/조치 출력 폴더, 진단 임시 폴더).
        throw "결과 폴더 접근 권한을 제한하지 못해 중단함($Path): $($_.Exception.Message)"
    }
}

function New-PrivateTempFile {
    <# 진단 중 외부 명령(secedit/auditpol)이 쓰는 임시 파일 경로를 돌려준다(W-R7). 예전의 %TEMP%\kisa-secedit-<PID>.inf
       처럼 예측 가능한 이름은 SYSTEM 실행 시(C:\Windows\Temp) 일반 사용자가 미리 만들어 두거나 링크로 바꿔 정책 값을
       위조(거짓 양호)할 수 있었다. 무작위 이름의 새 폴더를 만들어(이미 있으면 실패) 실행자·Administrators·SYSTEM 만
       접근하게 한 뒤 그 안의 경로를 준다. 호출자는 사용 후 폴더째(Split-Path -Parent) 지운다 #>
    param([Parameter(Mandatory)][string]$FileName)
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("kisa-" + [System.IO.Path]::GetRandomFileName())
    if (Test-Path -LiteralPath $dir) { throw "임시 폴더가 이미 존재함(선점 의심): $dir" }
    New-PrivateDirectory -Path $dir
    return (Join-Path $dir $FileName)
}

function Invoke-NativeCommand {
    <# 외부 실행 파일을 시간 제한 안에서 실행한다(운영 안전 기준 S2, W-R16 - secedit/auditpol/bcdedit 이 서비스 이상 시
       무기한 대기할 수 있었다). 반환: ExitCode / Output(줄 배열) / ErrorText / TimedOut. 시간 초과 시 프로세스를 끝내고
       TimedOut=$true(ExitCode=$null). 실행 파일을 찾지 못하는 등 시작 자체의 실패는 예외로 던진다 #>
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @(), [int]$TimeoutSec = 60)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (@($ArgumentList) | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    # 자식은 콘솔 없이(CreateNoWindow) 실행되므로 시스템 OEM 코드페이지(한글판 cp949)로 출력한다 - 그 코드페이지로 디코딩
    try {
        $enc = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $psi.StandardOutputEncoding = $enc; $psi.StandardErrorEncoding = $enc
    } catch { }
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            return [PSCustomObject]@{ ExitCode = $null; Output = @(); ErrorText = ""; TimedOut = $true }
        }
        $p.WaitForExit()
        return [PSCustomObject]@{
            ExitCode = $p.ExitCode
            Output = @($outTask.Result -split "\r?\n")
            ErrorText = $errTask.Result
            TimedOut = $false
        }
    } finally { $p.Dispose() }
}

function Invoke-CimCmdletWithTimeout {
    <# Get-SmbShare·Get-SmbShareAccess·Get-NetFirewallProfile 같은 CDXML cmdlet 은 -OperationTimeoutSec 기본값이 적용되지
       않아 WMI 가 멈추면 무기한 대기한다(W-R16). -AsJob(같은 프로세스 안의 CIM 작업)으로 실행해 시간을 제한한다.
       시간 초과·조회 오류(권한 거부 등)는 예외로 던진다 - 호출부가 "결과 없음"과 구분할 수 있게(W-R2) #>
    param([Parameter(Mandatory)][string]$Command, [hashtable]$Parameters = @{}, [int]$TimeoutSec = 60)
    $job = & $Command @Parameters -AsJob
    try {
        if (-not (Wait-Job -Job $job -Timeout $TimeoutSec)) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            throw "$Command 시간 초과(${TimeoutSec}초)"
        }
        # 작업 안의 오류(권한 거부 등)는 작업 상태가 Completed 여도 Receive-Job 에서 다시 던져진다
        $out = Receive-Job -Job $job -ErrorAction Stop
        if ($job.State -eq 'Failed') { throw "$Command 실패: $($job.ChildJobs[0].JobStateInfo.Reason.Message)" }
        return $out
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

# ---- SID 기반 비교 (W-R2/W-R3/W-R9/W-R15) ----------------------------------------
# 비영문 OS 에서는 내장 계정·그룹 이름이 번역된다(예: 독일어 Everyone=Jeder, Administrators=Administratoren).
# 이름 문자열 비교는 그런 OS 에서 아무것도 찾지 못해 거짓 양호가 되므로 잘 알려진 SID 로 비교한다.
# (S-1-1-0 Everyone, S-1-5-32-544 Administrators, S-1-5-32-545 Users, S-1-5-11 Authenticated Users,
#  S-1-5-32-555 Remote Desktop Users, S-1-5-18 SYSTEM)

function Get-AclAllowRulesForSids {
    <# 파일/폴더 ACL 에서 지정한 SID 들에 대한 허용(Allow) ACE 만 돌려준다. IdentityReference 를 SID 형식으로 받아
       비교하므로 OS 언어와 무관하다 #>
    param([Parameter(Mandatory)]$Acl, [Parameter(Mandatory)][string[]]$Sids)
    return @($Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) |
            Where-Object { $_.AccessControlType -eq 'Allow' -and $Sids -contains $_.IdentityReference.Value })
}

function ConvertTo-SidString {
    <# 계정 이름(NTAccount) → SID 문자열. 이미 SID 형식이면 그대로, 변환 실패 시 $null #>
    param([Parameter(Mandatory)][string]$Name)
    $n = $Name.TrimStart('*')
    if ($n -match '^S-1-[\d-]+$') { return $n }
    try { return (New-Object System.Security.Principal.NTAccount($n)).Translate([System.Security.Principal.SecurityIdentifier]).Value }
    catch { return $null }
}

function Get-SecurityCenterProducts {
    <# root\SecurityCenter2 의 타사 백신/방화벽 제품 목록(Microsoft Defender 자체는 제외). W-R4/W-R11.
       반환: Ok(조회 성공 여부), Error, Products(Name, Enabled, State). 서버 OS 에는 SecurityCenter2 가 없어 Ok=$false.
       Enabled 는 productState 의 두 번째 바이트 0x10 비트로 판단한다 - Microsoft 공식 문서는 없고 제조사·보안 업계에서
       공통으로 쓰는 해석(0x10/0x11=켜짐, 0x00/0x01=꺼짐)이다. 예전에는 등록만 되어 있으면(꺼져 있어도) "활성"으로 봤다 #>
    param([Parameter(Mandatory)][ValidateSet('AntiVirusProduct', 'FirewallProduct')][string]$Class)
    try {
        $items = @(Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName $Class -OperationTimeoutSec 30 -ErrorAction Stop)
    } catch {
        return [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message; Products = @() }
    }
    $prods = @($items | Where-Object { "$($_.pathToSignedProductExe)" -notlike 'windowsdefender:*' -and "$($_.displayName)" -notmatch 'Defender' } |
            ForEach-Object {
                $st = [int64]$_.productState
                [PSCustomObject]@{ Name = "$($_.displayName)"; Enabled = ((($st -shr 8) -band 0x10) -ne 0); State = ('0x{0:X6}' -f $st) }
            })
    return [PSCustomObject]@{ Ok = $true; Error = ""; Products = $prods }
}

function Get-LocalGroupMembersBySid {
    <# 내장 로컬 그룹을 SID 로 조회한다(W-R9). 예전에는 Get-LocalGroupMember 를 영문 그룹 이름("Remote Desktop Users")
       으로 불러 비영문 OS 에서 실패했고, 고아 SID(삭제된 도메인 계정)가 섞인 그룹에서도 Get-LocalGroupMember 가
       실패한다 - 그 경우 ADSI(WinNT)로 한 번 더 조회한다. 둘 다 실패하면 예외. 반환: Name / ObjectClass / SID #>
    param([Parameter(Mandatory)][string]$Sid)
    $firstErr = ""
    try {
        return @(Get-LocalGroupMember -SID $Sid -ErrorAction Stop | ForEach-Object {
                [PSCustomObject]@{ Name = "$($_.Name)"; ObjectClass = "$($_.ObjectClass)"; SID = "$($_.SID)" } })
    } catch { $firstErr = $_.Exception.Message }
    try {
        $gname = (New-Object System.Security.Principal.SecurityIdentifier($Sid)).Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $g = [ADSI]"WinNT://$env:COMPUTERNAME/$gname,group"
        return @($g.psbase.Invoke('Members') | ForEach-Object {
                $t = $_.GetType()
                $path = "$($t.InvokeMember('ADsPath', 'GetProperty', $null, $_, $null))"
                $cls = "$($t.InvokeMember('Class', 'GetProperty', $null, $_, $null))"
                $msid = ""
                try { $msid = (New-Object System.Security.Principal.SecurityIdentifier([byte[]]$t.InvokeMember('objectSid', 'GetProperty', $null, $_, $null), 0)).Value } catch { }
                [PSCustomObject]@{ Name = (($path -replace '^WinNT://', '') -replace '/', '\'); ObjectClass = $cls; SID = $msid }
            })
    } catch {
        throw "그룹($Sid) 구성원 조회 실패: $firstErr / ADSI: $($_.Exception.Message)"
    }
}

function New-OutputDir {
    param([string]$BaseDir, [string]$CategoryNum)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    # 같은 초에 두 번 실행해도 결과가 섞이지 않도록 PID 를 붙인다('-' 구분이라 merge.py 규칙과 호환)
    $outDir = Join-Path $BaseDir "$($env:COMPUTERNAME)_${CategoryNum}_$ts-$PID"
    New-PrivateDirectory -Path $outDir
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "raw") | Out-Null
    $Script:RunLogPath = Join-Path $outDir "run.log"
    New-Item -ItemType File -Force -Path $Script:RunLogPath | Out-Null
    return $outDir
}

function Test-IsElevatedAdmin {
    <# 현재 토큰이 Administrators(S-1-5-32-544) 권한으로 실행 중인지(UAC 로 권한이 낮춰진 토큰이면 $false).
       02/03/07 run.ps1 이 비관리자 실행의 GOOD/NA 를 ERROR 로 바꾸는 데 쓴다(sh 의 nonroot_unverified 와 같은 원칙) -
       CI 실측: 비관리자 실행에서 서비스·IIS 설정 조회가 조용히 실패해 W-18 VULN→NA, W-33 VULN→GOOD, IIS 전 항목 NA #>
    try {
        $p = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([System.Security.Principal.SecurityIdentifier]'S-1-5-32-544')
    } catch { return $false }
}

function Get-ServiceChecked {
    <# 서비스 조회. 있으면 서비스 객체, 실제로 없으면 $null, 조회 자체가 실패(권한 부족 등)하면 예외.
       예전 checks 는 Get-Service -ErrorAction SilentlyContinue 로 "조회 실패"를 "서비스 없음/중지"로 읽어, 비관리자(배치
       로그온) 실행에서 W-33 이 GOOD, W-41 이 VULN 이었다(CI 실측). 서비스 관리자가 "없음"이라고 해도 레지스트리
       Services\<이름> 키가 있으면 조회 실패로 본다 #>
    param([Parameter(Mandatory)][string]$Name)
    try {
        $s = Get-Service -Name $Name -ErrorAction Stop
        # F-W18(1.4.0): ServiceController 는 표시 이름으로도 찾는다 - "Browser" 가 표시 이름이 Browser 인 커널 드라이버 bowser 로
        # 잡혀(항상 Running) W-18 이 늘 VULN 이었다(양방향 케이스로 확인). 서비스 이름이 정확히 같은 것만 인정한다.
        if ($s -and $s.Name -ne $Name) { return $null }
        return $s
    } catch {
        $msg = $_.Exception.Message
        if ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound -and
            -not (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name")) {
            return $null
        }
        throw "서비스 '$Name' 조회 실패: $msg"
    }
}

function Test-IsDomainController {
    <# DomainRole 4/5 = 백업/주 도메인 컨트롤러. DC 에는 로컬 SAM 이 없어 Win32_UserAccount 조회가 도메인
       전체 계정 열거(LDAP 대량 조회)가 될 수 있으므로 계정 열거형 check 는 DC 에서 건너뛴다 #>
    if ($null -ne $Global:IsDcCache) { return $Global:IsDcCache }
    $Global:IsDcUnknown = $false
    try {
        $Global:IsDcCache = ((Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 30 -ErrorAction Stop).DomainRole -ge 4)
        return $Global:IsDcCache
    } catch { }
    # W-R14: 예전에는 CIM 실패를 "DC 아님($false)"으로 캐시해 DC 에서 W-16 이 SYSVOL/NETLOGON 을 VULN 으로 냈다.
    # 레지스트리 ProductOptions\ProductType(LanmanNt = 도메인 컨트롤러 - Microsoft 문서의 WinNT/ServerNT/LanmanNt)로 대체 확인한다.
    try {
        $pt = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name ProductType -ErrorAction Stop).ProductType
        $Global:IsDcCache = ($pt -eq 'LanmanNt')
        return $Global:IsDcCache
    } catch { }
    # 둘 다 실패: 판별 불가. 캐시하지 않고 IsDcUnknown 를 세운 뒤 $true 를 돌려 계정 열거형 check(W-01~03)는
    # MANUAL 로 빠지게 한다(DC 일 수 있으니 대량 조회를 피함). W-16 은 IsDcUnknown 을 보고 SYSVOL/NETLOGON 을 단정하지 않는다.
    $Global:IsDcUnknown = $true
    return $true
}

function Protect-SecretText {
    <# 명령줄 등 자유 텍스트에서 흔한 자격증명 패턴의 값을 *** 로 가린다(증적 저장 전 적용).
       예) "net use \\s\c /user:dom\u P@ss" / "app.exe -password x" / "pwd=x;" / ConvertTo-SecureString "x" #>
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text
    # W-R13: --password x / --password=x(이중 대시), schtasks /rp x 도 같은 규칙으로 가린다
    $t = $t -replace '(?i)((?:^|\s)(?:--|[-/])(?:p|pw|pwd|pass|passwd|password|rp)(?:\s+|[:=]))(?![-/])("[^"]*"|''[^'']*''|\S+)', '$1***'
    $t = $t -replace '(?i)((?:password|passwd|pwd|secret|token|apikey|api_key)\s*[=:]\s*)("[^"]*"|''[^'']*''|[^\s;&]+)', '$1***'
    $t = $t -replace '(?i)(/user:\S+\s+)(?![-/])(\S+)', '$1***'
    $t = $t -replace '(?i)(ConvertTo-SecureString\s+(?:-String\s+)?)("[^"]*"|''[^'']*'')', '$1***'
    # W-R13: mysql 계열의 붙여 쓴 비밀번호(-pSECRET). 다른 명령의 -path 등을 지우지 않도록 mysql 류 명령줄에서만,
    # 대소문자 구분(-P 는 포트)으로 가린다
    if ($t -match '(?i)\b(?:mysql|mysqldump|mysqladmin|mysqlimport|mariadb|mariadb-dump)(?:\.exe)?\b') {
        $t = $t -creplace '(\s-p)(?=[^\s*])("[^"]*"|''[^'']*''|\S+)', '$1***'
    }
    # W-R13: curl -u user:pass / --user=user:pass, URL 에 박힌 자격증명(scheme://user:pass@host)
    $t = $t -replace '(?i)((?:^|\s)(?:-u|--user)(?:\s+|=)["'']?[^\s:"'']+:)([^\s"'']+)', '$1***'
    $t = $t -replace '(?i)(\b[a-z][a-z0-9+.-]*://[^/\s:@]+:)([^@\s/]+)(@)', '$1***$3'
    # W-R13: net user <id> <pw> (계정 생성·비밀번호 변경), net use \\srv\share <pw> (/user: 앞에 오는 비밀번호)
    $t = $t -replace '(?i)(\bnet1?(?:\.exe)?\s+user\s+(?:"[^"]+"|\S+)\s+)(?![/])("[^"]*"|\S+)', '$1***'
    $t = $t -replace '(?i)(\bnet1?(?:\.exe)?\s+use\s+(?:[a-z]:\s+|\*\s+)?\\\\\S+\s+)(?![/])("[^"]*"|\S+)', '$1***'
    return $t
}

function New-CheckResult {
    <# 각 checks/*.ps1 이 반환할 결과 객체를 표준화 #>
    param(
        [string]$Code,
        [ValidateSet("VULN","MANUAL","ERROR","NA","GOOD")][string]$Status,
        [string]$Detail = "",
        [string]$Evidence = ""
    )
    return [PSCustomObject]@{ code = $Code; status = $Status; detail = $Detail; evidence = $Evidence }
}

function Save-ResultJson {
    param([array]$Results, [string]$OutFile, [string]$Category, [string]$OsFamily)
    # R-10: 항목이 1개면 파이프라인이 결과를 풀어 items 가 배열이 아니라 객체로 저장됐다(보고서 빈 화면, merge.py
    # TypeError) - @() 로 항상 배열을 유지한다.
    $sorted = @($Results | Sort-Object @{Expression={$StatusOrder[$_.status]}}, code)
    $obj = [ordered]@{
        tool_version  = $Script:ToolVersion
        guide_version = $Script:GuideVersion
        category      = $Category
        host          = $env:COMPUTERNAME
        env           = $OsFamily
        generated_at  = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
        items         = $sorted
    }
    # R-11: pwsh 7 의 ConvertTo-Json 은 < > & 를 이스케이프하지 않아, 증적 속 "</script>" 가 report.html(결과 JSON 을
    # <script> 블록에 그대로 이어붙임) 안에서 스크립트를 끝내고 뒤의 내용을 실행시킬 수 있었다. JSON 문법상 이 문자들은
    # 문자열 안에만 나오므로 \u003c 등으로 바꿔도 값은 같다(PS 5.1 은 원래 이렇게 출력).
    # X-01(1.3.4): 1.3.2 에서는 이 치환이 '<'→'<' 로 저장돼 아무것도 바꾸지 않았다(편집 도구가 이스케이프를 풀어 씀) -
    # 바이트로 확인할 것: grep -c 'u003c' lib/Common.psm1
    $json = ($obj | ConvertTo-Json -Depth 6) -join "`n"
    $json = $json.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026')
    $json | Out-File -FilePath $OutFile -Encoding utf8
}

function New-ReportHtml {
    <# lib/report/{head,mid,tail}.html + guide.json + result.json 을 순서대로 이어붙여 단일 report.html 생성 #>
    param([string]$LibDir, [string]$GuideJson, [string]$ResultJson, [string]$OutHtml)
    $parts = @(
        (Join-Path $LibDir "report\head.html"),
        $GuideJson,
        (Join-Path $LibDir "report\mid.html"),
        $ResultJson,
        (Join-Path $LibDir "report\tail.html")
    )
    $content = ($parts | ForEach-Object { Get-Content -Raw -Encoding utf8 -Path $_ }) -join ""
    Set-Content -Path $OutHtml -Value $content -Encoding utf8 -NoNewline
}

# ---- 레지스트리 값 조회 (부재 시 예외 없이 $null) --------------------------------
function Test-RegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        # W-R14: 키/값이 없는 것(ObjectNotFound / InvalidArgument)과 권한 거부 등 "조회 실패"를 구분한다. 실패는
        # $Global:RegistryQueryFailed 로 남겨 02_windows/07_pc run.ps1 이 그 항목의 GOOD/VULN 을 ERROR 로 바꾼다
        # (반환값은 호출부 호환을 위해 그대로 $null).
        $cat = $_.CategoryInfo.Category
        if ($cat -ne [System.Management.Automation.ErrorCategory]::ObjectNotFound -and
            $cat -ne [System.Management.Automation.ErrorCategory]::InvalidArgument) {
            $Global:RegistryQueryFailed = $true
            $Global:RegistryQueryError = "$Path\$Name : $($_.Exception.Message)"
        }
        return $null
    }
}

# ---- secedit 기반 로컬 보안 정책 조회 ---------------------------------------------
# secedit /export 결과([System Access], [Privilege Rights] 등)를 1회만 내보내 캐시한다.
# 비밀번호/계정 잠금 정책, 사용자 권한 할당(User Rights Assignment)처럼 단순 레지스트리 값이
# 아닌 정책은 이 방법으로만 조회 가능하다 (SAM/LSA 정책 객체이기 때문).
function Get-SecEditExport {
    if ($Script:SecEditCache) { return $Script:SecEditCache }

    # W-R7: 임시 파일은 무작위 이름의 전용 폴더(New-PrivateTempFile)에 만들고, 종료 코드와 필수 섹션을 확인한다 -
    # 예전에는 예측 가능한 %TEMP% 경로를 썼고, 부분 내보내기(종료 코드 비정상)도 그대로 파싱해 W-49 등이 거짓 VULN 이었다.
    # W-R16: 시간 제한(120초). 실행 파일은 PATH 가 아니라 System32 경로로 지정한다.
    $sections = @{}
    $tmp = $null; $why = ""
    try {
        $tmp = New-PrivateTempFile -FileName "secedit.inf"
        $exe = Join-Path $env:SystemRoot "System32\secedit.exe"
        $r = Invoke-NativeCommand -FilePath $exe -ArgumentList @('/export', '/cfg', $tmp, '/quiet') -TimeoutSec 120
        if ($r.TimedOut) { $why = "시간 초과(120초)" }
        elseif ($r.ExitCode -ne 0) { $why = "종료 코드 $($r.ExitCode)" }
        elseif (-not (Test-Path -LiteralPath $tmp)) { $why = "내보내기 파일이 생성되지 않음" }
        else {
            $current = $null
            foreach ($line in Get-Content -LiteralPath $tmp -Encoding Unicode) {
                $t = $line.Trim()
                if ($t -match '^\[(.+)\]$') {
                    $current = $Matches[1]
                    $sections[$current] = @{}
                } elseif ($current -and $t -match '^([^=]+?)\s*=\s*(.*)$') {
                    $sections[$current][$Matches[1].Trim()] = $Matches[2].Trim()
                }
            }
            if (-not ($sections.ContainsKey('System Access') -and $sections.ContainsKey('Privilege Rights') -and
                    $sections['System Access'].Count -gt 0 -and $sections['Privilege Rights'].Count -gt 0)) {
                $why = "필수 섹션([System Access]/[Privilege Rights]) 누락 - 부분 내보내기"
            }
        }
    } catch {
        $why = $_.Exception.Message
    } finally {
        if ($tmp) { Remove-Item -LiteralPath (Split-Path -Parent $tmp) -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if ($why) {
        Write-Log "secedit /export 실패: $why" "WARN"
        $sections = @{}
    }
    $Script:SecEditCache = $sections
    # 내보내기 실패(관리자 권한 없음 등)면 모든 정책 값이 $null 로 보여 "미설정 = 취약/양호"로 오판된다.
    # 02_windows/07_pc run.ps1 이 이 플래그로 해당 항목의 GOOD/VULN 을 ERROR 로 바꾼다.
    $Global:SecEditFailed = ($sections.Count -eq 0)
    return $sections
}

function Clear-SecEditCache {
    <# 보안 정책을 바꾼 뒤(fix 적용·원복) 다음 조회가 새로 내보내도록 캐시를 비운다 #>
    $Script:SecEditCache = $null
}

function Get-SecPolicyValue {
    <# [System Access] 등 단순 key=value 섹션에서 값을 조회. 없으면 $null #>
    param([Parameter(Mandatory)][string]$Section, [Parameter(Mandatory)][string]$Name)
    $Global:SecPolicyQueried = $true
    $exp = Get-SecEditExport
    if ($exp.ContainsKey($Section) -and $exp[$Section].ContainsKey($Name)) {
        return $exp[$Section][$Name]
    }
    return $null
}

function ConvertFrom-Sid {
    <# "*S-1-5-32-544" 형태의 SID 문자열을 계정/그룹 이름으로 변환. 실패 시 원본 SID 반환 #>
    param([Parameter(Mandatory)][string]$SidToken)
    $sid = $SidToken.TrimStart('*')
    if ($sid -notmatch '^S-1-[\d-]+$') { return $sid }   # secedit 이 이름으로 남긴 계정
    # W-R16: 도메인 SID 를 이름으로 바꾸려면 DC 에 질의하는데, DC 에 닿지 않으면 SID 마다 오래 대기한다. 이 컴퓨터
    # 안에서 풀리는 SID(BUILTIN S-1-5-32-*, 잘 알려진 S-1-1-0·S-1-5-<n>, 서비스/IIS 가상 계정, 이 컴퓨터의 로컬 계정)만
    # 변환하고 나머지는 SID 그대로 둔다 - 판정은 SID 로 하므로(Get-SecPrivilegeSids) 증적 표시만 달라진다.
    if ($null -eq $Script:LocalMachineSidPrefix) {
        $Script:LocalMachineSidPrefix = ""
        try {
            $u = Get-LocalUser -ErrorAction Stop | Select-Object -First 1
            if ($u -and $u.SID.AccountDomainSid) { $Script:LocalMachineSidPrefix = "$($u.SID.AccountDomainSid.Value)-" }
        } catch { }
    }
    $local = ($sid -match '^S-1-[0-3]-\d+$' -or $sid -match '^S-1-5-\d+$' -or $sid -match '^S-1-5-(32|80|82|83|90|96)-' -or
        ($Script:LocalMachineSidPrefix -and $sid.StartsWith($Script:LocalMachineSidPrefix)))
    if (-not $local) { return $sid }
    try {
        $account = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount])
        return $account.Value
    } catch {
        return $sid
    }
}

function Get-SecPrivilegeAccounts {
    <# [Privilege Rights] 의 SeXxxPrivilege 값을 계정/그룹 이름 배열로 반환 (없으면 빈 배열) #>
    param([Parameter(Mandatory)][string]$Right)
    $Global:SecPolicyQueried = $true
    $raw = Get-SecPolicyValue -Section "Privilege Rights" -Name $Right
    if (-not $raw) { return @() }
    return $raw -split ',' | Where-Object { $_ } | ForEach-Object { ConvertFrom-Sid $_.Trim() }
}

function Get-SecPrivilegeSids {
    <# [Privilege Rights] 값을 SID 문자열 배열로 반환(W-R15: 이름 비교는 비영문 OS 에서 "Administrators" 가 번역돼 실패).
       secedit 이 SID 대신 이름으로 남긴 계정은 SID 로 변환을 시도하고, 실패하면 이름 그대로 둔다 #>
    param([Parameter(Mandatory)][string]$Right)
    $Global:SecPolicyQueried = $true
    $raw = Get-SecPolicyValue -Section "Privilege Rights" -Name $Right
    if (-not $raw) { return @() }
    return @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
            $s = ConvertTo-SidString -Name $_
            if ($s) { $s } else { $_.TrimStart('*') }
        })
}

# ---- MSSQL 연결/쿼리 (08_dbms) ---------------------------------------------------
# sqlcmd.exe 를 사용한다(MSSQL 설치 시 기본 동봉되는 mssql-tools, 대상 무설치 원칙 준수).
# 비밀번호는 인자로 절대 넘기지 않고 SQLCMDPASSWORD 환경변수로만 전달한다
# (run.ps1 이 $env:DB_PASSWORD 를 이 변수에 매핑, 08_dbms/CLAUDE.md "접속정보 취급" 원칙).
# $Global:DbQueryOk 로 "쿼리 실패"와 "쿼리 성공+결과 0건"을 구분한다(PC-15에서 배운 원칙과 동일).
# 운영 안전장치: -l(로그인 제한 시간)/-t(쿼리 제한 시간)로 무기한 대기를 막고, run.ps1/fix.ps1 이
# Test-MssqlPreflight 로 접속을 1회만 시험해 실패하면 $Global:DbConnFailed 를 세워 이후 호출은
# 접속하지 않는다 - 잘못된 비밀번호로 항목 수만큼 로그인을 반복해 CHECK_POLICY=ON 로그인(sa 포함)이
# Windows 계정 잠금 임계값에 걸려 잠기는 것을 막는다.
function Invoke-MssqlQuery {
    param([Parameter(Mandatory)][string]$Sql)
    if ($Global:DbConnFailed) {
        $Global:DbQueryOk = $false
        "DB 접속 사전 점검 실패로 접속하지 않음(계정 잠금 방지): $Global:DbConnFailMsg" | Out-File -FilePath $Global:DbErrFile -Encoding utf8
        return $null
    }
    # -C: 서버 인증서를 검증 없이 신뢰. mssql-tools18 은 암호화 연결을 강제하고 인증서 검증에 실패하면 접속이 안 돼
    # 자체 서명 인증서가 흔한 로컬 인스턴스에는 필요하다. 다만 원격 SQL 인증에서 무조건 신뢰하면 중간자가 인증서를
    # 바꿔 끼워 비밀번호를 가로챌 수 있어(진단 검수 D-R8), 원격 대상은 인증서를 검증하고 운영자가
    # $env:DB_TRUST_SERVER_CERT=1 로 명시했을 때만 -C 를 붙인다.
    $sqlArgs = @('-h', '-1', '-W', '-s', '|', '-b', '-l', '5', '-t', '60')
    if ($env:DB_TRUST_SERVER_CERT -eq '1' -or -not (Test-MssqlRemoteTarget)) { $sqlArgs += @('-C') }
    $target = if ($env:DB_HOST) { $env:DB_HOST } else { 'localhost' }
    if ($env:DB_PORT) { $target = "$target,$($env:DB_PORT)" }
    $sqlArgs += @('-S', $target)
    if ($env:DB_USER) { $sqlArgs += @('-U', $env:DB_USER) } else { $sqlArgs += @('-E') }
    if ($env:DB_NAME) { $sqlArgs += @('-d', $env:DB_NAME) }
    $sqlArgs += @('-Q', $Sql)
    try {
        $out = & sqlcmd @sqlArgs 2>$Global:DbErrFile
        $Global:DbQueryOk = ($LASTEXITCODE -eq 0)
        # PS 5.1 은 stderr 를 오류 레코드 형식("SQLCMD.EXE : ... At ...psm1:294 char:16", "+ CategoryInfo ...")으로 쓴다 -
        # 결과 detail 에 스크립트 위치 같은 잡음이 남지 않게 sqlcmd 메시지만 남긴다
        if (-not $Global:DbQueryOk -and (Test-Path $Global:DbErrFile)) {
            $clean = @(Get-Content -Path $Global:DbErrFile | Where-Object { $_ -notmatch '^\s*(At .+ char:\d+|\+|CategoryInfo|FullyQualifiedErrorId)' -and $_.Trim() } |
                ForEach-Object { $_ -replace '^\s*SQLCMD(\.EXE)?\s*:\s*', '' })
            $clean | Out-File -FilePath $Global:DbErrFile -Encoding utf8
        }
        return $out
    } catch {
        $Global:DbQueryOk = $false
        $_.Exception.Message | Out-File -FilePath $Global:DbErrFile -Encoding utf8
        return $null
    }
}

function Test-MssqlRemoteTarget {
    <# $env:DB_HOST(-SqlHost)가 이 PC 가 아니면 $true. 빈 값·"."·"(local)"·"(localdb)\..."·localhost·루프백·이 PC 의
       이름/IP 는 로컬. 원격이면 방화벽·레지스트리 기반 항목(D-10/D-13)이 분석자 PC 를 보게 되고(진단 검수 D-R1),
       인증서 무조건 신뢰(-C)도 하지 않는다(D-R8). 결과는 대상 문자열별로 캐시한다(DNS 조회 반복 방지). #>
    param([string]$Target = $env:DB_HOST)
    if ($null -ne $Global:MssqlRemoteCache -and $Global:MssqlRemoteCache.Target -eq "$Target") { return $Global:MssqlRemoteCache.Remote }
    $h = "$Target".Trim() -replace '^(tcp|np|lpc|admin):', ''
    $h = (($h -split ',')[0] -split '\\')[0].Trim().Trim('[', ']')
    $remote = $true
    if (-not $h -or $h -in @('.', '(local)', '(localdb)', 'localhost', '::1') -or $h -like '127.*') {
        $remote = $false
    } else {
        $names = @($env:COMPUTERNAME, [System.Net.Dns]::GetHostName())
        try { $names += [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).HostName } catch { $null = $_ }
        if (@($names | Where-Object { $_ -and ($_ -ieq $h -or ($_ -split '\.')[0] -ieq $h) }).Count -gt 0) {
            $remote = $false
        } else {
            $local = @()
            try {
                $local = @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                    ForEach-Object { $_.GetIPProperties().UnicastAddresses } | ForEach-Object { ($_.Address.ToString() -split '%')[0] })
            } catch { $null = $_ }
            $ip = $null
            $cands = @($h)
            if (-not [System.Net.IPAddress]::TryParse($h, [ref]$ip)) {
                try { $cands = @([System.Net.Dns]::GetHostAddresses($h) | ForEach-Object { ($_.ToString() -split '%')[0] }) } catch { $cands = @() }
            }
            foreach ($c in $cands) { if ($c -like '127.*' -or $c -eq '::1' -or $local -contains $c) { $remote = $false } }
        }
    }
    $Global:MssqlRemoteCache = @{ Target = "$Target"; Remote = $remote }
    return $remote
}

function Test-MssqlPreflight {
    <# 접속을 1회 시험. 실패하면 $Global:DbConnFailed/$Global:DbConnFailMsg 를 세우고 $false 반환 #>
    $Global:DbConnFailed = $false
    $Global:DbConnFailMsg = ""
    $null = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT 1;"
    if ($Global:DbQueryOk) { return $true }
    $msg = if (Test-Path $Global:DbErrFile) { (Get-Content -Path $Global:DbErrFile -TotalCount 2) -join " " } else { "" }
    if ($msg -match 'certificate|인증서|SSL Provider' -and $env:DB_TRUST_SERVER_CERT -ne '1') {
        $msg += " (원격 서버 인증서를 검증하지 못함 - 신뢰할 수 있는 인증서를 쓰거나, 위험을 이해한 경우에만 `$env:DB_TRUST_SERVER_CERT=1)"
    }
    $Global:DbConnFailMsg = $msg
    $Global:DbConnFailed = $true
    return $false
}

# ---- IIS 연동 (03_web IIS) --------------------------------------------------------
# WebAdministration 모듈은 IIS 관리 콘솔(IIS-WebServerManagementTools)이 설치된 Windows에만
# 존재한다. 모듈이 없으면 IIS 자체가 없다는 뜻이므로 모든 IIS check 는 NA 로 응답해야 한다.
# 가용 여부를 매 check 마다 다시 계산하지 않도록 프로세스 1회만 캐시한다.
function Test-IisAvailable {
    if ($null -ne $Global:IisAvailableCache) { return $Global:IisAvailableCache }
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $Global:IisAvailableCache = (Test-Path "IIS:\Sites")
    } catch {
        $Global:IisAvailableCache = $false
    }
    return $Global:IisAvailableCache
}

function Test-IisInstalledButUnreadable {
    <# IIS(W3SVC)는 설치돼 있는데 설정을 읽을 수 없는 경우(관리자 권한 없음 등). 예전에는 이를
       "IIS 미설치"로 오인해 전 항목이 NA(해당없음)로 나왔다 - 확인하지 못한 것을 해당없음으로 숨기지 않는다 #>
    if (Test-IisAvailable) { return $false }
    # 비관리자(배치 로그온) 실행에서는 Get-Service 자체가 실패해 "IIS 없음 → 전 항목 NA" 가 됐다(CI 실측).
    # 서비스 등록 여부는 레지스트리 키로 확인한다(일반 사용자도 읽기 가능).
    return (Test-IisInstalled)
}

function Test-IisInstalled {
    <# IIS(W3SVC 서비스) 설치 여부 - 레지스트리 Services\W3SVC 키 존재로 판단(권한과 무관) #>
    return (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\W3SVC")
}

function Get-IisSiteNames {
    <# 구성된 사이트 이름 목록 (IIS 미설치/사이트 없음이면 빈 배열) #>
    if (-not (Test-IisAvailable)) { return @() }
    try { return @(Get-Website -ErrorAction Stop | ForEach-Object { $_.Name }) }
    catch {
        # WEB-R7: 예전에는 조회 실패도 빈 배열 = "사이트 없음(NA)"이었다. 실패 표시를 남겨 03_web/run.ps1 이 그 항목의
        # NA/GOOD 을 ERROR 로 바꾼다.
        $Global:IisSiteListFailed = $true
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "사이트 목록(Get-Website): $($_.Exception.Message)"
        return @()
    }
}

function Get-IisSitePhysicalPath {
    <# 사이트의 실제 경로(환경변수 展開 완료). 조회 실패 시 $null(실패 표시 IisConfigQueryFailed, WEB-R7) #>
    param([Parameter(Mandatory)][string]$SiteName)
    try {
        $p = (Get-Website -Name $SiteName -ErrorAction Stop).physicalPath
        if (-not $p) {
            $Global:IisConfigQueryFailed = $true
            $Global:IisConfigQueryError = "physicalPath ($SiteName): 값 없음"
            return $null
        }
        return [System.Environment]::ExpandEnvironmentVariables($p)
    } catch {
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "physicalPath ($SiteName): $($_.Exception.Message)"
        return $null
    }
}

function Get-IisSiteConfigPaths {
    <# WEB-R8: 사이트 루트뿐 아니라 하위 application·virtual directory 의 설정 경로를 돌려준다(각자 web.config 로
       directoryBrowse·webdav·httpErrors 등을 재정의할 수 있는데 예전에는 사이트 루트만 봤다).
       반환: Label("site/app/vdir"), PSPath("IIS:\Sites\site\app\vdir"), IsApp(application 여부), AppPath("/app")
       하위 목록 조회에 실패하면 루트만 돌려주고 IisConfigQueryFailed 를 세운다(하위 경로 미검사를 GOOD 으로 넘기지 않음).
       한계: application/vdir 이 아닌 일반 하위 폴더의 web.config 는 열거하지 않는다 #>
    param([Parameter(Mandatory)][string]$SiteName)
    $root = "IIS:\Sites\$SiteName"
    $list = @([PSCustomObject]@{ Label = $SiteName; PSPath = $root; IsApp = $true; AppPath = "/" })
    $seen = @{ "/" = $true }
    try {
        $xp = "system.applicationHost/sites/site[@name='$SiteName']/application"
        foreach ($a in @(Get-WebConfiguration -PSPath "MACHINE/WEBROOT/APPHOST" -Filter $xp -ErrorAction Stop)) {
            $ap = "$($a.path)"
            if (-not $ap) { throw "application path 값 없음" }
            if (-not $seen.ContainsKey($ap)) {
                $seen[$ap] = $true
                $list += [PSCustomObject]@{ Label = "$SiteName$ap"; PSPath = $root + ($ap -replace '/', '\'); IsApp = $true; AppPath = $ap }
            }
        }
        foreach ($v in @(Get-WebConfiguration -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "$xp/virtualDirectory" -ErrorAction Stop)) {
            # 소속 application 경로는 요소의 ItemXPath(.../application[@path='/app']/virtualDirectory[@path='/v'])에서 얻는다
            if ("$($v.ItemXPath)" -notmatch "application\[@path='([^']*)'\]") { throw "virtualDirectory 소속 application 을 해석하지 못함: $($v.ItemXPath)" }
            $full = ($Matches[1].TrimEnd('/')) + "$($v.path)"
            if ($full -ne "/" -and $full.EndsWith('/')) { $full = $full.TrimEnd('/') }
            if (-not $full) { $full = "/" }
            if (-not $seen.ContainsKey($full)) {
                $seen[$full] = $true
                $list += [PSCustomObject]@{ Label = "$SiteName$full"; PSPath = $root + ($full -replace '/', '\'); IsApp = $false; AppPath = $Matches[1] }
            }
        }
    } catch {
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "하위 application/virtual directory 목록 ($SiteName): $($_.Exception.Message)"
    }
    return $list
}

function Get-IisConfigValue {
    <# Get-WebConfigurationProperty 래퍼 - 사이트 지정 시 IIS:\Sites\<site>, 미지정 시 서버 전체
       기본값(MACHINE/WEBROOT/APPHOST)에서 설정값을 조회. 속성이 없거나 조회 실패 시 $null #>
    param(
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Name,
        [string]$SiteName = "",
        [string]$PSPath = ""   # WEB-R8: 하위 application/vdir 경로(Get-IisSiteConfigPaths 의 PSPath)를 직접 지정
    )
    try {
        if ($PSPath) {
            $v = Get-WebConfigurationProperty -PSPath $PSPath -Filter $Filter -Name $Name -ErrorAction Stop
        } elseif ($SiteName) {
            $v = Get-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter $Filter -Name $Name -ErrorAction Stop
        } else {
            $v = Get-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter $Filter -Name $Name -ErrorAction Stop
        }
        if ($null -eq $v) { return $null }
        if ($v.PSObject.Properties.Name -contains "Value") { return $v.Value }
        return $v
    } catch {
        # 호출부 다수가 "$null = 설정 없음(기본값)"으로 해석하므로 반환값은 유지하되, 조회 "실패"였다는
        # 사실을 남긴다. 03_web/run.ps1 이 이 플래그가 선 항목의 GOOD 을 ERROR 로 바꾼다(거짓 양호 방지).
        $Global:IisConfigQueryFailed = $true
        $Global:IisConfigQueryError = "$Filter/@$Name$(if ($PSPath) { " ($PSPath)" } elseif ($SiteName) { " ($SiteName)" }): $($_.Exception.Message)"
        return $null
    }
}

# ============================================================================
# ---- 자동 조치(fix) 공통 (§자동 조치, 루트 CLAUDE.md 참고) - Windows 계열 --------
# ============================================================================
# 01_unix/lib/common.sh 의 fix_* 계열과 같은 역할을 하는 PowerShell 버전이다. run.*/checks 는
# 이 함수들을 쓰지 않는다 - fix.ps1/fixes/*.ps1 전용.
#
# 백업 저장 구조: <FixBackupDir>\<코드>\{registry,service,acl,share}\*.json (자원 종류별 하위
# 폴더에 파일 하나당 자원 하나). 보안 정책(secedit, 비밀번호/잠금/사용자 권한 할당)은 레지스트리
# 값 하나처럼 개별 단위로 이전 값을 되돌릴 수 없는 전역 상태라, 실행 1회당 전체 스냅샷을
# <FixBackupDir>\_secpolicy\secedit-snapshot.inf 하나로만 백업한다 - 즉, secedit 기반 항목은
# "이 항목만" 롤백이 불가능하고 `fix.ps1 --rollback`(전체 원복)에서만 스냅샷 전체를 재적용한다
# (재검증 실패 시 자동 원복 경로에서는 다른 secedit 항목까지 되돌리지 않도록 일부러 건드리지 않음
# - 알려진 한계, CLAUDE.md에 기록).
#
# 여러 .ps1 파일(run.ps1/fix.ps1/각 checks·fixes 파일) 경계를 넘어 상태를 공유해야 하므로
# $Script: 가 아니라 $Global: 을 쓴다(교훈 18, MSSQL DbErrFile 버그와 동일한 이유).

function New-FixOutputDir {
    param([string]$BaseDir, [string]$CategoryNum)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $Global:FixOutDir = Join-Path $BaseDir "$($env:COMPUTERNAME)_${CategoryNum}_fix_$ts-$PID"
    $Global:FixBackupDir = Join-Path $Global:FixOutDir "backup"
    New-PrivateDirectory -Path $Global:FixOutDir
    New-Item -ItemType Directory -Force -Path $Global:FixBackupDir | Out-Null
    $Global:FixLog = Join-Path $Global:FixOutDir "changes.log"
    # 감사 로그(운영 안전 기준 F6): 누가 언제 어느 컴퓨터에서 바꿨는지 첫 줄에 남긴다. 각 기록 줄 앞에는
    # fix.ps1 이 시각을 붙인다(형식: 시각<TAB>코드<TAB>등급<TAB>결과<TAB>상세).
    "# 조치 실행 시작 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') / 컴퓨터 $($env:COMPUTERNAME) / 실행자 $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) / 도구 v$($Script:ToolVersion)" |
        Out-File -FilePath $Global:FixLog -Encoding utf8
    $Global:FixSecPolicyBackupFile = $null
    $Global:FixSecPolicyCodes = @()
    $Global:FixRollbackFailures = @()
    return $Global:FixOutDir
}

function Get-ResultVulnCodes {
    <# result.json(진단 결과)에서 status=VULN 인 코드만 배열로 반환 #>
    param([Parameter(Mandatory)][string]$ResultJson)
    $r = Get-Content -Raw -Encoding UTF8 -Path $ResultJson | ConvertFrom-Json
    return @($r.items | Where-Object { $_.status -eq "VULN" } | ForEach-Object { $_.code })
}

function Test-FixResultTarget {
    <# X-06(1.3.4): 조치 입력 result.json 이 이 컴퓨터·이 카테고리의 진단 결과인지 확인한다. 예전에는 아무 결과나 받아
       다른 서버(또는 오래된) 결과로 -Apply -Yes 를 돌리면 auto 항목이 확인 없이 바뀌었다(원복에만 호스트 확인이 있었음).
       불일치는 -Force 없이는 거부, 7일 넘은 결과는 -Force 가 아니면 대화형 확인을 받는다. 통과하면 $true. #>
    param([Parameter(Mandatory)][string]$ResultJson, [Parameter(Mandatory)][string]$Category, [switch]$Force)
    try { $r = Get-Content -Raw -Encoding UTF8 -Path $ResultJson | ConvertFrom-Json } catch {
        Write-Host "result.json 을 읽을 수 없음: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    $problems = @()
    if ("$($r.host)" -ne "$($env:COMPUTERNAME)") { $problems += "호스트 불일치(결과: $($r.host), 현재: $($env:COMPUTERNAME))" }
    if ("$($r.category)" -ne $Category) { $problems += "카테고리 불일치(결과: $($r.category), 기대: $Category)" }
    if ($problems.Count -gt 0) {
        if ($Force) { Write-Warning ("-Force 로 계속: " + ($problems -join " / ")); return $true }
        Write-Host ("이 result.json 은 이 대상의 진단 결과가 아닙니다 - " + ($problems -join " / ") + ". 변경 없이 중단(의도한 경우 -Force).") -ForegroundColor Red
        return $false
    }
    $gen = [datetime]::MinValue
    if (-not [datetime]::TryParse("$($r.generated_at)", [ref]$gen)) {
        $problems += "진단 시각(generated_at)을 해석할 수 없음: $($r.generated_at)"
    } elseif (((Get-Date) - $gen).TotalDays -gt 7) {
        $problems += "진단 결과가 7일 이상 지남($($r.generated_at)) - 그 사이 설정이 바뀌었을 수 있음"
    }
    if ($problems.Count -eq 0 -or $Force) {
        if ($problems.Count -gt 0) { Write-Warning ("-Force 로 계속: " + ($problems -join " / ")) }
        return $true
    }
    return (Read-FixConfirm -Prompt (($problems -join " / ") + " - 그래도 이 결과로 조치를 진행합니까? [y/N]"))
}

# ---- 운영 안전 가드 (운영 안전 기준 F1·F6, 1.2.2) ------------------------------------
# 백업 실패는 "[백업 실패]" 로 시작하는 예외로 던진다. fixes/*.ps1 은 백업을 변경보다 먼저 하므로
# 예외가 나면 그 조치는 아무것도 바꾸지 않은 채 멈추고, fix.ps1 은 이 접두어를 보고 해당 항목을
# 원복한 뒤 실행 전체를 중단한다(예전에는 백업 실패를 삼키고 변경을 계속했다).
function Test-FixIsAdmin {
    if ([System.Environment]::OSVersion.Platform -ne 'Win32NT') { return ((& id -u) -eq '0') }
    $p = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-FixInteractive {
    <# 사람이 직접 답할 수 있는 콘솔인지. 입력 리다이렉트("y" | fix.ps1)도 비대화형으로 본다 - sh 쪽이
       /dev/tty 에서만 답을 읽어 파이프로 확인을 우회할 수 없게 한 것과 같은 원칙 #>
    try { if ([Console]::IsInputRedirected) { return $false } } catch { }
    return [Environment]::UserInteractive
}

function Read-FixConfirm {
    <# y/Y 만 승인. 비대화형이거나 Read-Host 가 실패(-NonInteractive 등)하면 항상 "아니오" #>
    param([Parameter(Mandatory)][string]$Prompt)
    if (-not (Test-FixInteractive)) {
        Write-Host "$Prompt -> 비대화형 실행이라 '아니오'로 처리"
        return $false
    }
    try { $ans = Read-Host $Prompt } catch { return $false }
    return ($ans -match '^[yY]$')
}

function Get-FixRollbackNote {
    <# 조치 파일 머리말의 "# 원복: ..." 표기. 없으면 빈 값(= 백업으로 원복 가능). 원복할 수 없거나 일부만
       되돌아가는 조치를 적용 "전에" 알리기 위함(운영 안전 기준 F4) #>
    param([Parameter(Mandatory)][string]$File)
    if (-not (Test-Path -LiteralPath $File)) { return "" }
    $line = Get-Content -LiteralPath $File -Encoding UTF8 -TotalCount 12 | Where-Object { $_ -like "# 원복: *" } | Select-Object -First 1
    if ($line) { return $line.Substring("# 원복: ".Length) }
    return ""
}

function Confirm-FixPlan {
    <# -Apply 시 실제로 바뀔 항목을 먼저 보여주고 1회 확인. auto 등급은 항목별 확인 없이 적용되므로
       예전처럼 -Apply 만으로 경고 없이 auto 전체가 적용되던 것을 막는다. -Yes 는 이 확인만 생략 #>
    param([Parameter(Mandatory)][string[]]$Codes, [Parameter(Mandatory)][hashtable]$GuideByCode, [switch]$Yes, [string]$FixDir = "")
    if ($Yes) { return $true }
    Write-Host "다음 항목을 실제로 변경합니다:"
    $nAuto = 0
    foreach ($c in $Codes) {
        $m = $GuideByCode[$c]
        $g = if ($m -and $m.fix) { $m.fix } else { "manual" }
        $t = if ($m) { $m.title } else { $c }
        if ($g -eq "auto") { Write-Host ("  [auto]    {0,-8} {1}  <- 개별 확인 없이 적용" -f $c, $t); $nAuto++ }
        elseif ($g -eq "confirm") { Write-Host ("  [confirm] {0,-8} {1}  <- 적용 직전 항목별로 다시 확인" -f $c, $t) }
        $rb = if ($FixDir) { Get-FixRollbackNote -File (Join-Path $FixDir "$c.ps1") } else { "" }
        if ($rb -and $g -in @("auto", "confirm")) { Write-Host "            └ 원복: $rb" -ForegroundColor Yellow }
    }
    return (Read-FixConfirm -Prompt "위 목록대로 진행하시겠습니까? (auto $nAuto 건은 추가 확인 없이 적용됨) [y/N]")
}

function Enter-FixLock {
    <# 같은 카테고리 조치의 동시 실행 방지(서로의 백업을 덮어쓰고 같은 설정을 번갈아 바꾸는 것 방지).
       획득하면 Mutex 객체, 다른 실행이 잡고 있으면 $null. 비정상 종료로 버려진 잠금은 인수한다 #>
    param([Parameter(Mandatory)][string]$CategoryNum)
    $m = $null
    foreach ($scope in @("Global", "Local")) {
        try { $m = New-Object System.Threading.Mutex($false, "$scope\kisa-infra-audit-fix-$CategoryNum"); break } catch { $m = $null }
    }
    if (-not $m) { return $null }
    $got = $false
    try { $got = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { $m.Dispose(); return $null }
    return $m
}

function Exit-FixLock {
    param($Mutex)
    if ($Mutex) { try { $Mutex.ReleaseMutex() } catch { }; $Mutex.Dispose() }
}

function Save-FixBackupJson {
    <# 백업 JSON 저장. 같은 항목에서 같은 자원을 다시 백업하면 첫 백업(조치 전 원본)을 보존하고
       건너뛴다 - 예전에는 두 번째 백업이 이미 바뀐 값으로 덮어써 원복해도 원래대로 돌아가지 않았다 #>
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)]$Object, [int]$Depth = 4)
    if (Test-Path -LiteralPath $File) { return $File }
    try {
        $Object | ConvertTo-Json -Depth $Depth | Set-Content -Path $File -Encoding UTF8 -ErrorAction Stop
    } catch {
        throw "[백업 실패] $File 기록 실패: $($_.Exception.Message)"
    }
    return $File
}

function Get-FixItemBackupDir {
    <# 현재 $Global:FixCode 에 대응하는 백업 디렉터리를 만들고 경로를 반환 #>
    param([string]$Sub = "")
    $d = Join-Path $Global:FixBackupDir $Global:FixCode
    if ($Sub) { $d = Join-Path $d $Sub }
    try { New-Item -ItemType Directory -Force -Path $d -ErrorAction Stop | Out-Null }
    catch { throw "[백업 실패] 백업 디렉터리 생성 실패($d): $($_.Exception.Message)" }
    return $d
}

# ---- 레지스트리 값 백업/설정/원복 -------------------------------------------------
function Backup-FixRegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $dir = Get-FixItemBackupDir -Sub "registry"
    $safe = ("$Path--$Name") -replace '[\\:\s]', '_'
    $file = Join-Path $dir "$safe.json"
    if (Test-Path -LiteralPath $file) { return $file }
    $existed = $false; $value = $null; $kind = $null
    if (Test-Path -LiteralPath $Path) {
        # 읽기에 실패했는데 "원래 값 없음"으로 기록하면 원복 때 실제로 있던 값을 지워 버리므로 중단한다.
        try {
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            if ($item.GetValueNames() -contains $Name) {
                $existed = $true
                $value = $item.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $kind = $item.GetValueKind($Name).ToString()
            }
        } catch {
            throw "[백업 실패] 기존 레지스트리 값을 읽을 수 없음($Path\$Name): $($_.Exception.Message)"
        }
    }
    # 자동 로그온 비밀번호(W-52/PC-12 의 DefaultPassword)처럼 비밀값은 평문으로 백업 파일에 남기지 않는다 -
    # DPAPI(ConvertFrom-SecureString)로 암호화해 같은 계정·같은 컴퓨터에서만 복호화되게 한다.
    $protected = $false
    if ($existed -and $Name -match 'Password' -and $value) {
        $ss = New-Object System.Security.SecureString
        foreach ($ch in "$value".ToCharArray()) { $ss.AppendChar($ch) }
        $ss.MakeReadOnly()
        $value = $ss | ConvertFrom-SecureString
        $ss.Dispose()
        $protected = $true
    }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ Path = $Path; Name = $Name; Existed = $existed; Value = $value; Kind = $kind; Protected = $protected }))
}

function Add-FixRollbackFailure {
    <# 원복 실패/불가를 누적한다(운영 안전 기준 F4). 예전 Restore-* 는 모든 오류를 catch { } 로 삼키고 fix.ps1 은
       항상 "원복됨"으로 기록해, 실제로 되돌아가지 않은 변경을 운영자가 알 수 없었다 #>
    param([Parameter(Mandatory)][string]$Message)
    $Global:FixRollbackFailures = @($Global:FixRollbackFailures) + "[$($Global:FixRollbackCode)] $Message"
}

function Register-FixNoRollback {
    <# 표준 백업 형식이 없는 자원(DNS 영역·auditpol·이벤트 로그 크기·공유 삭제·IIS 컬렉션 등)을 바꾸는 조치가
       변경 전에 호출한다. Restore-FixItem 이 이 표시를 보고 "원복 불가"로 보고한다 #>
    param([Parameter(Mandatory)][string]$Reason)
    $f = Join-Path (Get-FixItemBackupDir) "_norollback.txt"
    try { Add-Content -Path $f -Value $Reason -Encoding UTF8 -ErrorAction Stop }
    catch { throw "[백업 실패] 원복 불가 표시 기록 실패: $($_.Exception.Message)" }
}

function Restore-FixRegistryBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    try {
        if ($o.Existed) {
            $value = $o.Value
            if ($o.Protected) {
                # DPAPI 로 보호해 둔 값(자동 로그온 비밀번호 등) - 같은 계정·같은 컴퓨터에서만 복호화된다
                $ss = ConvertTo-SecureString -String $o.Value -ErrorAction Stop
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
                try { $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
                finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            }
            if (-not (Test-Path -LiteralPath $o.Path)) { New-Item -Path $o.Path -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -Path $o.Path -Name $o.Name -PropertyType $o.Kind -Value $value -Force -ErrorAction Stop | Out-Null
        } elseif (Test-Path -LiteralPath $o.Path) {
            $item = Get-Item -LiteralPath $o.Path -ErrorAction Stop
            if ($item.GetValueNames() -contains $o.Name) { Remove-ItemProperty -Path $o.Path -Name $o.Name -ErrorAction Stop }
        }
    } catch { Add-FixRollbackFailure "레지스트리 원복 실패 $($o.Path)\$($o.Name): $($_.Exception.Message)" }
}

function Set-FixRegistryValue {
    <# 백업 후 레지스트리 값을 설정. fix 스크립트가 $Global:FixStatus/Detail/Evidence 를 직접
       채우지 않아도 되도록 대표 케이스(값 1개 설정)를 감싼 얇은 래퍼 - U-16류 fix_set_owner_perm
       과 같은 역할 #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = "DWord"
    )
    Backup-FixRegistryValue -Path $Path -Name $Name | Out-Null
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "$Path : $Name = $Value ($Type) 로 설정함"
    $Global:FixEvidence = "$Path\$Name = $((Get-ItemProperty -Path $Path -Name $Name).$Name)"
}

function Remove-FixRegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    Backup-FixRegistryValue -Path $Path -Name $Name | Out-Null
    if (Test-Path -LiteralPath $Path) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "$Path : $Name 값을 제거함"
    $Global:FixEvidence = ""
}

# ---- 서비스 상태 백업/비활성화/원복 ------------------------------------------------
function Backup-FixServiceState {
    param([Parameter(Mandatory)][string]$Name)
    $dir = Get-FixItemBackupDir -Sub "service"
    $file = Join-Path $dir "$Name.json"
    if (Test-Path -LiteralPath $file) { return $file }
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    $found = [bool]$svc
    $startType = if ($svc) { $svc.StartType.ToString() } else { $null }
    $status = if ($svc) { $svc.Status.ToString() } else { $null }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ Name = $Name; Found = $found; StartType = $startType; Status = $status }))
}

function Restore-FixServiceBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    if (-not $o.Found) { return }
    try {
        Set-Service -Name $o.Name -StartupType $o.StartType -ErrorAction Stop
        if ($o.Status -eq "Running") { Start-Service -Name $o.Name -ErrorAction Stop }
        # F-W41(1.4.0): 조치가 시작한 서비스(원래 중지)는 다시 중지한다 - 예전에는 시작 유형만 되돌려 구동 상태가 남았다
        elseif ($o.Status -eq "Stopped" -and (Get-Service -Name $o.Name).Status -ne "Stopped") { Stop-Service -Name $o.Name -Force -ErrorAction Stop }
    } catch { Add-FixRollbackFailure "서비스 원복 실패 $($o.Name): $($_.Exception.Message)" }
}

function Disable-FixService {
    <# check_service_disabled(사실상 Get-Service 로 직접 확인) 과 짝을 이루는 조치 헬퍼.
       실행 중이면 중지 후 시작 유형을 Disabled 로 설정한다 #>
    param([Parameter(Mandatory)][string]$Name)
    Backup-FixServiceState -Name $Name | Out-Null
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        $Global:FixStatus = "NA"; $Global:FixDetail = "$Name 서비스가 존재하지 않음(이미 미설치)"; $Global:FixEvidence = ""
        return
    }
    try {
        if ($svc.Status -eq "Running") { Stop-Service -Name $Name -Force -ErrorAction Stop }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "$Name 서비스를 중지하고 시작 유형을 사용 안 함으로 설정함"
        $Global:FixEvidence = (Get-Service -Name $Name | Select-Object Name, Status, StartType | Out-String).Trim()
    } catch {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "$Name 서비스 비활성화 실패: $($_.Exception.Message)"
        $Global:FixEvidence = ""
    }
}

# ---- 기본(관리용) 공유 즉시 중지 (W-17 / PC-04) --------------------------------------
function Remove-FixDefaultShares {
    <# F-W17(1.4.0): 실행 중인 기본 공유(C$/ADMIN$ 등)를 지운다. 예전 조치는 Remove-SmbShare 실패를 -ErrorAction SilentlyContinue 로
       삼키고 "즉시 제거"라고 보고했는데, Windows Server 2025 는 실행 중 기본 공유 삭제를 "The request is not supported" 로 거부한다
       (양방향 케이스 조치 검증에서 재진단 VULN). 삭제가 거부된 공유가 있으면 Server(LanmanServer) 서비스를 재시작해 레지스트리
       (AutoShareServer/AutoShareWks=0, 호출 전에 설정)대로 기본 공유 없이 다시 올린다 - 재시작 동안 SMB 연결이 끊긴다(confirm 등급).
       재시작에 딸려 멈춘 종속 서비스는 원래 실행 중이던 것만 다시 시작한다. 반환: @{ Removed; Restarted; Remaining } #>
    $isDefault = { param($n) $n -match '^[A-Za-z]\$$' -or $n -eq 'ADMIN$' }
    $before = @(Get-SmbShare -ErrorAction Stop | Where-Object { & $isDefault $_.Name } | ForEach-Object { $_.Name })
    $refused = @()
    foreach ($n in $before) {
        try { Remove-SmbShare -Name $n -Force -ErrorAction Stop } catch { $refused += $n }
    }
    $restarted = $false
    if ($refused.Count -gt 0) {
        $deps = @(Get-Service -Name LanmanServer -DependentServices | Where-Object { $_.Status -eq "Running" } | ForEach-Object { $_.Name })
        Restart-Service -Name LanmanServer -Force -ErrorAction Stop
        foreach ($d in $deps) { Start-Service -Name $d -ErrorAction SilentlyContinue }
        $restarted = $true
    }
    $remaining = @(Get-SmbShare -ErrorAction Stop | Where-Object { & $isDefault $_.Name } | ForEach-Object { $_.Name })
    return @{ Removed = @($before | Where-Object { $remaining -notcontains $_ }); Restarted = $restarted; Remaining = $remaining }
}

# ---- 로컬 계정 활성/비활성 상태 백업/원복 ------------------------------------------
function Backup-FixLocalAccountState {
    param([Parameter(Mandatory)][string]$Name)
    $dir = Get-FixItemBackupDir -Sub "account"
    $file = Join-Path $dir "$Name.json"
    if (Test-Path -LiteralPath $file) { return $file }
    $u = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    $enabled = if ($u) { $u.Enabled } else { $null }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ Name = $Name; Found = [bool]$u; Enabled = $enabled }))
}

function Restore-FixLocalAccountBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    if (-not $o.Found) { return }
    try {
        if ($o.Enabled) { Enable-LocalUser -Name $o.Name -ErrorAction Stop }
        else { Disable-LocalUser -Name $o.Name -ErrorAction Stop }
    } catch { Add-FixRollbackFailure "계정 상태 원복 실패 $($o.Name): $($_.Exception.Message)" }
}

function Set-FixLocalAccountDisabled {
    param([Parameter(Mandatory)][string]$Name, [bool]$Disabled = $true)
    Backup-FixLocalAccountState -Name $Name | Out-Null
    try {
        if ($Disabled) { Disable-LocalUser -Name $Name -ErrorAction Stop } else { Enable-LocalUser -Name $Name -ErrorAction Stop }
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "계정 '$Name' 을 $(if ($Disabled) { '비활성화' } else { '활성화' })함"
        $Global:FixEvidence = (Get-LocalUser -Name $Name | Select-Object Name, Enabled | Out-String).Trim()
    } catch {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "계정 '$Name' 상태 변경 실패: $($_.Exception.Message)"
        $Global:FixEvidence = ""
    }
}

# ---- 경로 전체 백업 후 삭제/원복 (03_web WEB-07/WEB-12: "삭제 자체가 조치") -----------
# 01_unix의 fix_backup_remove_path(tar)와 같은 역할의 PowerShell 버전. Windows PowerShell
# 5.1에는 tar가 항상 있다는 보장이 없어(Windows 10 1803+ 는 bsdtar 포함이지만 Server는 버전에
# 따라 다름) Copy-Item -Recurse 로 내용을 통째로 복사해 보존한다.
function Backup-FixPathAndRemove {
    <# 복사가 끝까지 성공하고 파일 수가 일치할 때만 삭제한다(예전에는 Copy-Item 실패와 무관하게 삭제).
       정션/심볼릭 링크는 거부한다 - PS 5.1 의 -Recurse 복사·삭제는 링크를 따라가 링크 대상(다른
       폴더·볼륨)의 실제 데이터를 복사하거나 지울 수 있고, 원복하면 링크가 아니라 실폴더로 되살아난다 #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "[백업 실패] $Path 는 정션/심볼릭 링크라 안전하게 백업·삭제할 수 없음(링크 대상 데이터 손상 위험) - 수동 조치 필요"
    }
    $dir = Get-FixItemBackupDir -Sub "remove"
    $safe = ($Path -replace '[\\:]', '_')
    $dest = Join-Path $dir $safe
    try {
        Copy-Item -LiteralPath $Path -Destination $dest -Recurse -Force -ErrorAction Stop
        $srcCount = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop).Count
        $dstCount = @(Get-ChildItem -LiteralPath $dest -Recurse -Force -ErrorAction Stop).Count
        if ($item.PSIsContainer -and $srcCount -ne $dstCount) { throw "파일 수 불일치(원본 $srcCount / 백업 $dstCount)" }
        Set-Content -Path "$dest.origpath.txt" -Value $Path -Encoding UTF8 -ErrorAction Stop
    } catch {
        throw "[백업 실패] 삭제 전 백업 실패 - 삭제하지 않음($Path): $($_.Exception.Message)"
    }
    # C-WEB07(1.4.0): 예전에는 삭제 실패(권한 부족·사용 중 파일)가 조용히 넘어가 일부만 지워진 채 APPLIED 로 보고됐다(CI: msadc).
    # 실패하면 지워진 부분을 백업에서 되살리고 예외로 알린다(호출부 fix.ps1 이 ERROR → 항목 원복으로 처리).
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
    catch {
        $why = $_.Exception.Message
        if ($item.PSIsContainer -and (Test-Path -LiteralPath $Path)) { Copy-Item -Path (Join-Path $dest '*') -Destination $Path -Recurse -Force -ErrorAction SilentlyContinue }
        elseif (-not (Test-Path -LiteralPath $Path)) { Copy-Item -LiteralPath $dest -Destination $Path -Recurse -Force -ErrorAction SilentlyContinue }
        throw "삭제 실패 - 지워진 부분을 백업에서 되살림($Path): $why"
    }
}

function Restore-FixPathRemoveBackup {
    param([Parameter(Mandatory)][string]$MetaFile)
    $orig = (Get-Content -Raw -Path $MetaFile).Trim()
    $src = $MetaFile -replace '\.origpath\.txt$', ''
    if (-not (Test-Path -LiteralPath $src)) { return }
    $parent = Split-Path -Parent $orig
    try {
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent -ErrorAction Stop | Out-Null }
        # 원래 폴더가 (일부 삭제 실패 등으로) 남아 있으면 그 안에 "폴더째" 복사돼 orig\<이름>\ 으로 중첩됐다(C-WEB07, CI 실측) - 내용만 복사
        if ((Test-Path -LiteralPath $orig -PathType Container) -and (Test-Path -LiteralPath $src -PathType Container)) {
            Copy-Item -Path (Join-Path $src '*') -Destination $orig -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -LiteralPath $src -Destination $orig -Recurse -Force -ErrorAction Stop
        }
    } catch { Add-FixRollbackFailure "삭제된 경로 복원 실패 ${orig}: $($_.Exception.Message)" }
}

# ---- IIS 애플리케이션 풀 identity 백업/설정/원복 (WEB-09) --------------------------
function Backup-FixAppPoolIdentity {
    param([Parameter(Mandatory)][string]$PoolName)
    $dir = Get-FixItemBackupDir -Sub "apppool"
    $file = Join-Path $dir "$PoolName.json"
    if (Test-Path -LiteralPath $file) { return $file }
    # C-WEB09(1.4.0): processModel.identityType 은 ConfigurationAttribute 가 아니라 문자열로 돌아와 .Value 가 늘 비었다 -
    # 백업이 빈 값이 되어 원복이 아무것도 하지 않았다(CI 실측). 두 형태 모두 처리
    try { $x = Get-ItemProperty "IIS:\AppPools\$PoolName" -Name processModel.identityType -ErrorAction Stop; $current = if ($null -ne $x -and $x.PSObject.Properties.Name -contains "Value") { $x.Value } else { $x } }
    catch { throw "[백업 실패] 애플리케이션 풀 '$PoolName' 현재 identity 를 읽을 수 없음: $($_.Exception.Message)" }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ PoolName = $PoolName; IdentityType = "$current" }))
}

function Restore-FixAppPoolIdentityBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    if (-not $o.IdentityType) { return }
    # C-WEB09(1.4.0): fix.ps1 -Rollback 프로세스는 WebAdministration 을 불러오지 않아 IIS: 드라이브가 없었다(CI 실측 - 백업이 늘 빈 값이라
    # 그동안 이 경로가 실행된 적이 없었음)
    try { Import-Module WebAdministration -ErrorAction Stop; Set-ItemProperty "IIS:\AppPools\$($o.PoolName)" -Name processModel.identityType -Value $o.IdentityType -ErrorAction Stop }
    catch { Add-FixRollbackFailure "앱 풀 identity 원복 실패 $($o.PoolName): $($_.Exception.Message)" }
}

function Set-FixAppPoolIdentity {
    param([Parameter(Mandatory)][string]$PoolName, [Parameter(Mandatory)][string]$IdentityType)
    Backup-FixAppPoolIdentity -PoolName $PoolName | Out-Null
    try {
        Set-ItemProperty "IIS:\AppPools\$PoolName" -Name processModel.identityType -Value $IdentityType -ErrorAction Stop
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "애플리케이션 풀 '$PoolName' identityType 을 $IdentityType 로 설정함"
        $Global:FixEvidence = ""
    } catch {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "애플리케이션 풀 '$PoolName' identityType 설정 실패: $($_.Exception.Message)"
        $Global:FixEvidence = ""
    }
}

# ---- IIS/FTP 서버 설정(WebAdministration) 값 백업/설정/원복 ------------------------
# W-23(FTP 익명 인증) 등 레지스트리가 아니라 applicationHost.config 기반 설정을 바꾸는 소수
# 항목 전용. 03_web(IIS)의 Get-IisConfigValue 와 달리 여기서는 값을 직접 바꿔야 하므로 별도
# Set-/Backup-/Restore- 세트를 둔다(모듈 재사용 범위: 03_web IIS 웹사이트 설정과 Windows FTP
# 서버 설정은 PSPath 필터만 다를 뿐 같은 WebAdministration 공급자를 쓴다).
function Backup-FixWebConfigProperty {
    <# -Location: MACHINE/WEBROOT/APPHOST 의 <location path="사이트"> 에 쓰는 경우(잠긴 섹션) #>
    param([Parameter(Mandatory)][string]$Filter, [Parameter(Mandatory)][string]$Name, [string]$PSPath = "IIS:\", [string]$Location = "")
    $dir = Get-FixItemBackupDir -Sub "webconfig"
    $safe = ("$PSPath--$Location--$Filter--$Name") -replace '[\\:/\s\[\]@=''"*?<>|]', '_'
    $file = Join-Path $dir "$safe.json"
    if (Test-Path -LiteralPath $file) { return $file }
    $loc = @{}; if ($Location) { $loc.Location = $Location }
    # 읽기 실패를 $null 로 기록하면 원복 때 설정을 빈 값으로 덮어쓰므로 중단한다.
    try {
        $v = Get-WebConfigurationProperty -Filter $Filter -Name $Name -PSPath $PSPath @loc -ErrorAction Stop
        $value = ConvertTo-FixPlainValue $v
    } catch { throw "[백업 실패] IIS 설정 현재 값을 읽을 수 없음($PSPath $Location [$Filter] $Name): $($_.Exception.Message)" }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ Filter = $Filter; Name = $Name; PSPath = $PSPath; Location = $Location; Value = $value }))
}

function ConvertTo-FixPlainValue {
    <# Get-WebConfigurationProperty 결과를 백업 JSON 에 넣을 단순 값으로 바꾼다. 열거형 속성(httpErrors@errorMode 등)은
       NoteProperty 가 붙은 문자열로 돌아오는데, PS 5.1 ConvertTo-Json 은 이를 {"value":"Detailed",...} 객체로 저장해
       원복 때 Set-WebConfigurationProperty 가 그 객체를 받아 값을 바꾸지 못했다(오류도 없이 - CI 에서 WEB-22 원복 후에도
       GOOD 으로 실측). ConfigurationAttribute 면 .Value, 그 밖에는 ETS 래퍼를 벗긴 원래 값(BaseObject)을 쓴다.
       예전 형식의 백업({value: ...} 객체)도 원복 시 이 함수로 풀린다 #>
    param($Value)
    if ($null -eq $Value) { return $null }
    $names = @($Value.PSObject.Properties.Name)
    if ($Value -isnot [string] -and $names -contains "Value") { $Value = $Value.Value }
    elseif ($Value -is [System.Management.Automation.PSCustomObject] -and $names -contains "value") { $Value = $Value.value }
    if ($null -eq $Value) { return $null }
    return $Value.PSObject.BaseObject
}

function Restore-FixWebConfigPropertyBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    $loc = @{}; if ($o.Location) { $loc.Location = $o.Location }
    $want = ConvertTo-FixPlainValue $o.Value
    try {
        Set-WebConfigurationProperty -Filter $o.Filter -Name $o.Name -Value $want -PSPath $o.PSPath @loc -ErrorAction Stop
        # 원복을 "성공"으로 보고하기 전에 실제로 그 값이 되었는지 다시 읽어 확인한다(운영 안전 기준 F4 - 오류 없이 값이
        # 바뀌지 않는 경우가 있었음)
        $now = ConvertTo-FixPlainValue (Get-WebConfigurationProperty -Filter $o.Filter -Name $o.Name -PSPath $o.PSPath @loc -ErrorAction Stop)
        if ("$now" -ne "$want") { throw "다시 읽은 값이 '$now'(기대 '$want')" }
    } catch { Add-FixRollbackFailure "IIS 설정 원복 실패 $($o.PSPath) $($o.Location) [$($o.Filter)] $($o.Name): $($_.Exception.Message)" }
}

function Set-FixWebConfigProperty {
    <# 사이트(IIS:\Sites\<이름>) 에 쓰기가 실패하면 - asp, security/access, webdav/authoring 처럼 기본적으로
       사이트 web.config 위임이 막힌(overrideModeDefault=Deny) 섹션 - 같은 값을 applicationHost.config 의
       <location path="<이름>"> 에 쓴다(IIS 관리자에서 사이트 설정을 바꿀 때와 같은 위치). 결과는 호출부의 check 재실행이 검증한다 #>
    param(
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$PSPath = "IIS:\"
    )
    $bk = Join-Path (Get-FixItemBackupDir -Sub "webconfig") "_"
    $existed = @(Get-ChildItem -Path (Split-Path $bk) -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $file = Backup-FixWebConfigProperty -Filter $Filter -Name $Name -PSPath $PSPath
    try {
        Set-WebConfigurationProperty -Filter $Filter -Name $Name -Value $Value -PSPath $PSPath -ErrorAction Stop
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "$PSPath [$Filter] $Name = $Value 로 설정함"
        $Global:FixEvidence = ""
        return
    } catch {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "$PSPath [$Filter] $Name 설정 실패: $($_.Exception.Message)"
        $Global:FixEvidence = ""
    }
    if ($PSPath -notmatch '^IIS:\\Sites\\(.+)$') { return }
    # 하위 application/virtual directory(IIS:\Sites\site\app\vdir, F-R3)는 location 경로 "site/app/vdir" 로 쓴다
    $site = $Matches[1] -replace '\\', '/'
    # 사이트 경로 쓰기는 실패해 아무것도 바뀌지 않았다 - 그 백업을 남기면 원복 때 같은 쓰기가 다시 실패해 "원복 실패"로 잘못 보고된다
    if ($existed -notcontains $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    $first = $Global:FixDetail
    Backup-FixWebConfigProperty -Filter $Filter -Name $Name -PSPath "MACHINE/WEBROOT/APPHOST" -Location $site | Out-Null
    try {
        Set-WebConfigurationProperty -Filter $Filter -Name $Name -Value $Value -PSPath "MACHINE/WEBROOT/APPHOST" -Location $site -ErrorAction Stop
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "applicationHost.config <location path=`"$site`"> [$Filter] $Name = $Value 로 설정함(사이트 web.config 위임 불가)"
    } catch {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "$first / applicationHost.config location 설정도 실패: $($_.Exception.Message)"
    }
}

function Invoke-FixIisRemoveServerHeader {
    <# IIS Server 응답 헤더 제거(requestFiltering@removeServerHeader = true) - 03_web WEB-16 과 02_windows W-33 이 함께 쓴다.
       F-R3: 진단은 서버 전역 값뿐 아니라 사이트별 유효 값(사이트 web.config·location 재정의)도 본다(W-33 은 실제 응답 헤더).
       서버 전역이 true 가 아니면 true 로 바꾼 뒤, 사이트마다 다시 읽어 여전히 true 가 아닌(재정의한) 사이트를 true 로 고친다.
       예전에는 전역만 바꿔 사이트 재정의가 남으면 재검증 실패 → 원복으로 끝났다(CI: W-33 이 IIS 픽스처의 사이트 재정의로 실측).
       결과는 $Global:FixStatus/Detail(APPLIED/NA/ERROR) #>
    $Global:FixEvidence = ""
    if (-not (Test-IisAvailable)) { $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; return }
    $filter = "system.webServer/security/requestFiltering"
    $Global:IisConfigQueryFailed = $false
    $removeHeader = Get-IisConfigValue -Filter $filter -Name "removeServerHeader"
    if ($null -eq $removeHeader) {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "removeServerHeader 속성을 지원하지 않는 IIS 버전으로 추정됨(또는 조회 실패) - URL Rewrite 등 대체 수단을 수동으로 구성할 것"
        return
    }
    $applied = @(); $failed = @()
    if ($removeHeader -ne $true) {
        Set-FixWebConfigProperty -Filter $filter -Name "removeServerHeader" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST"
        if ($Global:FixStatus -eq "APPLIED") { $applied += "서버 전역" } else { $failed += "서버 전역: $($Global:FixDetail)" }
    }
    if ($failed.Count -eq 0) {
        $Global:IisSiteListFailed = $false
        $sites = @(Get-IisSiteNames)
        if ($Global:IisSiteListFailed) { $failed += "사이트 목록 조회 실패: $($Global:IisConfigQueryError)" }
        foreach ($site in $sites) {
            $Global:IisConfigQueryFailed = $false
            $v = Get-IisConfigValue -Filter $filter -Name "removeServerHeader" -SiteName $site
            if ($Global:IisConfigQueryFailed) { $failed += "${site}: 조회 실패 $($Global:IisConfigQueryError)"; continue }
            # WEB-16 진단과 같은 기준: 사이트 유효 값이 있고 true 가 아니면 사이트가 재정의한 것
            if ($null -eq $v -or $v -eq $true) { continue }
            Set-FixWebConfigProperty -Filter $filter -Name "removeServerHeader" -Value $true -PSPath "IIS:\Sites\$site"
            if ($Global:FixStatus -eq "APPLIED") { $applied += $site } else { $failed += "${site}: $($Global:FixDetail)" }
        }
    }
    $Global:IisConfigQueryFailed = $false
    $Global:FixEvidence = ""
    if ($failed.Count -gt 0) {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "조치 실패: $($failed -join ' / ')$(if ($applied) { " (적용됨: $($applied -join ', '))" })"
    } elseif ($applied.Count -gt 0) {
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "removeServerHeader = true 로 설정함: $($applied -join ', ')"
    } else {
        $Global:FixStatus = "NA"
        $Global:FixDetail = "이미 Server 헤더가 제거되도록 설정되어 있음(사이트 재정의 없음)"
    }
}

function Invoke-FixIisConfigPaths {
    <# F-R3: 진단(03_web WEB-04/18/22)이 Get-IisSiteConfigPaths 로 보는 모든 위치(사이트 루트 + 하위 application·
       virtual directory)를 같은 순서(루트 먼저)로 읽어, -IsVuln 이 참인 위치만 -Value 로 고친다. 예전 조치는 사이트 루트만
       고쳐, 하위 경로가 자기 web.config/location 으로 재정의한 경우 재검증 VULN → 원복으로 끝났다.
       상위를 고치면 상속받던 하위는 다시 읽을 때 정상이라 건너뛴다. 결과는 $Global:FixStatus/Detail 에 집계한다:
       고친 곳이 있고 실패가 없으면 APPLIED, 쓰기·조회 실패가 하나라도 있으면 ERROR(조회 실패를 "대상 없음"으로 넘기지 않음), 대상이 없으면 NA #>
    param(
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][scriptblock]$IsVuln,
        [Parameter(Mandatory)][string]$What
    )
    $Global:FixEvidence = ""
    if (-not (Test-IisAvailable)) { $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; return }
    $sites = @(Get-IisSiteNames)
    if ($sites.Count -eq 0) {
        if ($Global:IisSiteListFailed) { $Global:FixStatus = "ERROR"; $Global:FixDetail = "IIS 사이트 목록 조회 실패: $($Global:IisConfigQueryError)" }
        else { $Global:FixStatus = "NA"; $Global:FixDetail = "구성된 IIS 웹사이트가 없음" }
        return
    }
    $applied = @(); $failed = @()
    foreach ($site in $sites) {
        $Global:IisConfigQueryFailed = $false
        $paths = @(Get-IisSiteConfigPaths -SiteName $site)
        if ($Global:IisConfigQueryFailed) { $failed += "${site}: $($Global:IisConfigQueryError)" }
        foreach ($cp in $paths) {
            $Global:IisConfigQueryFailed = $false
            $cur = Get-IisConfigValue -Filter $Filter -Name $Name -PSPath $cp.PSPath
            if ($Global:IisConfigQueryFailed) { $failed += "$($cp.Label): 조회 실패 $($Global:IisConfigQueryError)"; continue }
            if (-not (& $IsVuln $cur)) { continue }
            Set-FixWebConfigProperty -Filter $Filter -Name $Name -Value $Value -PSPath $cp.PSPath
            if ($Global:FixStatus -eq "APPLIED") { $applied += $cp.Label } else { $failed += "$($cp.Label): $($Global:FixDetail)" }
        }
    }
    # 위 루프가 조회 실패 표시를 지웠으므로, 실패는 아래 ERROR 로만 전달한다
    $Global:IisConfigQueryFailed = $false
    $Global:FixEvidence = ""
    if ($failed.Count -gt 0) {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "조치 실패: $($failed -join ' / ')$(if ($applied) { " (적용됨: $($applied -join ', '))" })"
    } elseif ($applied.Count -gt 0) {
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "$What 사이트/경로: $($applied -join ', ')"
    } else {
        $Global:FixStatus = "NA"
        $Global:FixDetail = "대상 사이트/경로가 없음(이미 정상)"
    }
}

# ---- 방화벽 프로필 상태 백업/원복 (W-64/PC-15) -------------------------------------
function Backup-FixFirewallProfiles {
    $dir = Get-FixItemBackupDir -Sub "firewall"
    $file = Join-Path $dir "profiles.json"
    if (Test-Path -LiteralPath $file) { return $file }
    try { $profiles = @(Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled) }
    catch { throw "[백업 실패] 방화벽 프로필 상태를 읽을 수 없음: $($_.Exception.Message)" }
    return (Save-FixBackupJson -File $file -Object $profiles)
}

function Restore-FixFirewallProfilesBackup {
    param([Parameter(Mandatory)][string]$File)
    $items = @(Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json)
    foreach ($p in $items) {
        try { Set-NetFirewallProfile -Name $p.Name -Enabled $p.Enabled -ErrorAction Stop }
        catch { Add-FixRollbackFailure "방화벽 프로필 원복 실패 $($p.Name): $($_.Exception.Message)" }
    }
}

# ---- 방화벽을 안전하게 켜기 (W-64 / PC-15 / MSSQL D-10, 운영 안전 기준 F3, 1.3.0) --------------
function Test-FixFirewallPortAllowed {
    <# 활성화된 인바운드 Allow 규칙이 이 TCP 포트를 명시적으로 허용하는지(또는 프로그램 제한 없는 전체 허용).
       프로그램 지정 규칙(예: sqlservr.exe Any 포트)은 판별이 모호해 인정하지 않는다 - 보수적으로 "없음" #>
    param([Parameter(Mandatory)][int]$Port)
    $filters = @(Get-NetFirewallPortFilter -All -ErrorAction Stop | Where-Object {
        ($_.Protocol -eq "TCP" -and @($_.LocalPort) -contains "$Port") -or
        ($_.Protocol -in @("TCP", "Any") -and @($_.LocalPort) -contains "Any")
    })
    foreach ($f in $filters) {
        $r = $f | Get-NetFirewallRule -ErrorAction SilentlyContinue
        if (-not $r -or "$($r.Enabled)" -ne "True" -or "$($r.Direction)" -ne "Inbound" -or "$($r.Action)" -ne "Allow") { continue }
        if (@($f.LocalPort) -contains "$Port") { return $true }
        # 포트 Any 규칙은 "프로그램·앱 패키지·서비스 제한이 전혀 없는" 경우만 전체 허용으로 인정한다 - 스토어 앱
        # (AppX) 규칙은 Program=Any 로 보이지만 그 앱 패키지에만 적용된다(Windows Server 러너 실기에서 "Start",
        # "Work or school account" 등의 앱 규칙을 전체 허용으로 오인해, RDP 허용 규칙이 없는데도 켤 뻔했다).
        $app = $r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
        $svc = $r | Get-NetFirewallServiceFilter -ErrorAction SilentlyContinue
        if ($app -and "$($app.Program)" -eq "Any" -and -not "$($app.Package)" -and (-not $svc -or "$($svc.Service)" -eq "Any")) { return $true }
    }
    return $false
}

function Enable-FixFirewallSafely {
    <# 예전 조치는 "Remote Desktop" 같은 표시 이름(DisplayGroup)으로 원격 관리 규칙을 켰는데, 표시 이름은 OS
       언어에 따라 번역되어 한글 Windows 에서는 아무 규칙도 켜지지 않은 채 방화벽을 켰다(오류도 삼킴). 또 비표준
       RDP 포트·업무 포트(1433 등)는 확인하지 않았다.
       이제: ① 쓰고 있는 원격 관리(RDP 사용 시 / WinRM 실행 시)의 규칙 그룹만 리소스 ID 로 켜고(켠 규칙은 원복
       대상으로 기록) ② 현재 RDP 포트·WinRM 리스너 포트·호출부가 지정한 업무 포트를 허용하는 활성 인바운드
       규칙이 각각 있는지 확인해 ③ 하나라도 없으면 방화벽을 켜지 않는다(ERROR) #>
    param([int[]]$RequiredPorts = @(), [string]$Note = "")
    $ports = @($RequiredPorts | Where-Object { $_ })
    $groups = @()
    $ts = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue
    if ($ts -and $ts.fDenyTSConnections -eq 0) {
        $groups += '@FirewallAPI.dll,-28752'
        $rdpPort = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name PortNumber -ErrorAction SilentlyContinue).PortNumber
        $ports += $(if ($rdpPort) { [int]$rdpPort } else { 3389 })
    }
    $winrm = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    if ($winrm -and $winrm.Status -eq "Running") {
        $groups += '@FirewallAPI.dll,-30267'
        $lp = @(Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue | ForEach-Object {
            ($_ | Get-ChildItem -ErrorAction SilentlyContinue | Where-Object Name -eq "Port").Value })
        $ports += $(if ($lp.Count -gt 0) { $lp | ForEach-Object { [int]$_ } } else { 5985 })
    }

    try { $before = Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled }
    catch { $Global:FixStatus = "ERROR"; $Global:FixDetail = "Get-NetFirewallProfile 실행 실패: $($_.Exception.Message)"; $Global:FixEvidence = ""; return }

    # 켜기 전에 백업(프로필 상태 + 이번에 새로 켤 규칙 목록) - 실패하면 "[백업 실패]" 예외로 중단
    Backup-FixFirewallProfiles | Out-Null
    $dir = Get-FixItemBackupDir -Sub "firewall"
    $toEnable = @(foreach ($g in $groups) { Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue | Where-Object { "$($_.Enabled)" -ne "True" } })
    $rulesFile = Join-Path $dir "rules-enabled.txt"
    if (-not (Test-Path -LiteralPath $rulesFile)) {
        try { @($toEnable | ForEach-Object { $_.Name }) | Set-Content -Path $rulesFile -Encoding UTF8 -ErrorAction Stop }
        catch { throw "[백업 실패] 방화벽 규칙 목록 기록 실패: $($_.Exception.Message)" }
    }
    foreach ($r in $toEnable) { Enable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }

    $missing = @($ports | Select-Object -Unique | Where-Object { -not (Test-FixFirewallPortAllowed -Port $_) })
    if ($missing.Count -gt 0) {
        # 켜지 않기로 했으니 방금 켠 원격 관리 규칙도 되돌린다("변경 없음"으로 보고하면서 규칙만 바뀐 채 남지 않게)
        foreach ($r in $toEnable) { Disable-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "방화벽을 켜지 않음 - 다음 포트를 허용하는 활성 인바운드 규칙이 없어 켜는 즉시 접속이 끊길 수 있음: TCP $($missing -join ', '). 허용 규칙(필요 시 허용 IP 지정)을 먼저 만든 뒤 다시 실행"
        $Global:FixEvidence = "변경 전: " + (($before | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ", ")
        return
    }
    try {
        Set-NetFirewallProfile -All -Enabled True -ErrorAction Stop
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "모든 방화벽 프로필을 사용으로 설정함(허용 규칙 확인한 포트: TCP $((@($ports | Select-Object -Unique)) -join ', '), 새로 켠 원격 관리 규칙 $($toEnable.Count)개 - 원복 시 함께 되돌림)$Note"
        $Global:FixEvidence = "변경 전: " + (($before | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ", ")
    } catch {
        $Global:FixStatus = "ERROR"; $Global:FixDetail = "Set-NetFirewallProfile 실패: $($_.Exception.Message)"; $Global:FixEvidence = ""
    }
}

# ---- NTFS ACL 백업/원복 ------------------------------------------------------------
function Backup-FixAcl {
    param([Parameter(Mandatory)][string]$Path)
    $dir = Get-FixItemBackupDir -Sub "acl"
    $safe = ($Path -replace '[\\:]', '_')
    $file = Join-Path $dir "$safe.json"
    if (Test-Path -LiteralPath $file) { return $file }
    try { $acl = Get-Acl -Path $Path -ErrorAction Stop }
    catch { throw "[백업 실패] ACL 을 읽을 수 없음($Path): $($_.Exception.Message)" }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ Path = $Path; Sddl = $acl.Sddl }))
}

function Restore-FixAclBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    try {
        $acl = Get-Acl -Path $o.Path -ErrorAction Stop
        $acl.SetSecurityDescriptorSddlForm($o.Sddl)
        Set-Acl -Path $o.Path -AclObject $acl -ErrorAction Stop
    } catch { Add-FixRollbackFailure "ACL 원복 실패 $($o.Path): $($_.Exception.Message)" }
}

function Remove-FixAclIdentity {
    <# 지정한 정규식 패턴에 매칭되는 IdentityReference 의 허용(Allow) ACE 를 전부 제거한다
       (W-03/WEB-14류 "일반 사용자 그룹 접근 제거"와 짝을 이루는 조치 헬퍼) #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$IdentityPatterns)
    Backup-FixAcl -Path $Path | Out-Null
    $acl = Get-Acl -Path $Path
    $toRemove = @($acl.Access | Where-Object {
        $ident = $_.IdentityReference.Value
        ($IdentityPatterns | Where-Object { $ident -match $_ }).Count -gt 0
    })
    foreach ($rule in $toRemove) { [void]$acl.RemoveAccessRule($rule) }
    Set-Acl -Path $Path -AclObject $acl
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "$Path 에서 ACE $($toRemove.Count)개 제거함 (대상 패턴: $($IdentityPatterns -join ', '))"
    $Global:FixEvidence = (Get-Acl -Path $Path | Select-Object -ExpandProperty Access | Out-String).Trim()
}

# ---- SMB 공유 접근 권한 백업/원복 --------------------------------------------------
function Backup-FixShareAccess {
    param([Parameter(Mandatory)][string]$ShareName)
    $dir = Get-FixItemBackupDir -Sub "share"
    $file = Join-Path $dir "$ShareName.json"
    if (Test-Path -LiteralPath $file) { return $file }
    try {
        $access = @(Get-SmbShareAccess -Name $ShareName -ErrorAction Stop | Select-Object AccountName, AccessControlType, AccessRight)
    } catch { throw "[백업 실패] 공유 '$ShareName' 권한을 읽을 수 없음: $($_.Exception.Message)" }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ ShareName = $ShareName; Access = $access }))
}

function Restore-FixShareBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    foreach ($a in @($o.Access)) {
        try {
            Grant-SmbShareAccess -Name $o.ShareName -AccountName $a.AccountName -AccessRight $a.AccessRight -Force -ErrorAction Stop | Out-Null
        } catch { Add-FixRollbackFailure "공유 권한 원복 실패 $($o.ShareName)/$($a.AccountName): $($_.Exception.Message)" }
    }
}

function Revoke-FixShareEveryone {
    <# check(W-16/PC-04 등)가 찾아낸 "Everyone 권한이 있는 공유"에서 Everyone 만 제거 #>
    param([Parameter(Mandatory)][string]$ShareName)
    Backup-FixShareAccess -ShareName $ShareName | Out-Null
    try {
        Revoke-SmbShareAccess -Name $ShareName -AccountName "Everyone" -Force -ErrorAction Stop
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "공유 '$ShareName' 에서 Everyone 권한을 제거함"
        $Global:FixEvidence = (Get-SmbShareAccess -Name $ShareName | Out-String).Trim()
    } catch {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "공유 '$ShareName' Everyone 권한 제거 실패: $($_.Exception.Message)"
        $Global:FixEvidence = ""
    }
}

# ---- 보안 정책(secedit) 백업/적용/원복 ---------------------------------------------
# [System Access](비밀번호/잠금 정책 등)와 [Privilege Rights](사용자 권한 할당)는 레지스트리
# 값이 아니라 SAM/LSA 정책 객체라 secedit /configure 로만 바꿀 수 있다. 이 전역 상태는 항목별로
# "이전 값 하나만" 되돌릴 수 없으므로(사용자 권한 할당은 계정 목록 전체가 하나의 값), fix 실행
# 1회당 secedit /export 스냅샷을 한 번만 떠 두고 전체 --rollback 에서만 재적용한다.
function Backup-FixSecPolicy {
    if ($Global:FixSecPolicyBackupFile -and (Test-Path $Global:FixSecPolicyBackupFile)) {
        return $Global:FixSecPolicyBackupFile
    }
    $dir = Join-Path $Global:FixBackupDir "_secpolicy"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $snap = Join-Path $dir "secedit-snapshot.inf"
    secedit /export /cfg $snap /quiet | Out-Null
    # 스냅샷이 없으면 보안 정책을 되돌릴 방법이 없으므로 변경 전에 중단한다(예전에는 결과 미확인).
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $snap) -or (Get-Item $snap).Length -eq 0) {
        throw "[백업 실패] secedit /export 로 보안 정책 스냅샷을 만들지 못함(exit=$LASTEXITCODE)"
    }
    $Global:FixSecPolicyBackupFile = $snap
    return $Global:FixSecPolicyBackupFile
}

function Set-FixSecPolicyValue {
    <# $Section 예: "System Access" / "Privilege Rights" / "Kerberos Policy".
       $Values 는 그 섹션에 적용할 key=value 해시테이블(여러 개 가능) #>
    param([Parameter(Mandatory)][string]$Section, [Parameter(Mandatory)][hashtable]$Values)
    Backup-FixSecPolicy | Out-Null
    # 이 항목이 보안 정책을 바꿨음을 기록 - 항목 단위 원복 불가를 Restore-FixItem 이 정직하게 보고하도록
    $Global:FixSecPolicyCodes = @($Global:FixSecPolicyCodes) + $Global:FixCode
    # secedit /configure /db 는 .sdb 옆에 Jet 데이터베이스 부속 파일(.jfm, edb*.log 등)을 만든다 - 예전에는 %TEMP% 에 고정 이름으로
    # 만들고 .inf/.sdb 만 지워 .jfm 이 운영 서버 TEMP 에 남았다(CI fix_safety 실측). 전용 임시 폴더(New-PrivateTempFile)를 써서
    # 폴더째 지운다(예측 가능한 이름으로 정책 파일을 선점·위조당하는 것도 막는다 - 진단 쪽 W-R7 과 같은 이유).
    $tmp = New-PrivateTempFile -FileName "apply.inf"
    $tmpDir = Split-Path -Parent $tmp
    try {
        $lines = @("[Unicode]", "Unicode=yes", "[$Section]")
        foreach ($k in $Values.Keys) { $lines += "$k = $($Values[$k])" }
        $lines += @("[Version]", 'signature="$CHICAGO$"', "Revision=1")
        Set-Content -Path $tmp -Value $lines -Encoding Unicode
        $db = Join-Path $tmpDir "apply.sdb"
        $area = if ($Section -eq "Privilege Rights") { "USER_RIGHTS" } else { "SECURITYPOLICY" }
        $out = & secedit /configure /db $db /cfg $tmp /areas $area /quiet 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        # X-02: 정책을 바꿨으니 진단 캐시를 비운다 - 예전에는 같은 세션의 재검증이 변경 전 내보내기를 다시 읽어
        # 실제로 적용된 조치가 재검증 VULN → FAILED_NOT_ROLLED_BACK 으로 기록될 수 있었다.
        Clear-SecEditCache
    }
    if ($exitCode -eq 0) {
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "보안 정책[$Section] 적용: " + (($Values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", ")
        $Global:FixEvidence = $out
    } else {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "secedit /configure 실패(exit=$exitCode)"
        $Global:FixEvidence = $out
    }
}

function Set-FixSecPrivilege {
    <# $Sids 는 이미 '*S-1-5-32-544' 형태의 SID 토큰 배열(Get-SecPrivilegeAccounts 결과 역변환은
       호출부에서 처리) #>
    param([Parameter(Mandatory)][string]$Right, [Parameter(Mandatory)][string[]]$Sids)
    Set-FixSecPolicyValue -Section "Privilege Rights" -Values @{ $Right = ($Sids -join ",") }
}

function Restore-FixSecPolicyBackup {
    <# 전체 스냅샷을 통째로 재적용 - 개별 키 단위 원복이 불가능하므로 --rollback 전용 #>
    if (-not $Global:FixSecPolicyBackupFile -or -not (Test-Path $Global:FixSecPolicyBackupFile)) { return }
    # .sdb 옆에 생기는 .jfm 등 부속 파일까지 지우도록 전용 임시 폴더째 정리한다(Set-FixSecPolicyValue 와 같은 이유)
    $tmpDir = $null
    try {
        $db = New-PrivateTempFile -FileName "rollback.sdb"
        $tmpDir = Split-Path -Parent $db
        & secedit /configure /db $db /cfg $Global:FixSecPolicyBackupFile /areas SECURITYPOLICY, USER_RIGHTS /quiet | Out-Null
        if ($LASTEXITCODE -ne 0) { Add-FixRollbackFailure "보안 정책(secedit) 스냅샷 재적용 실패(exit=$LASTEXITCODE)" }
    } catch {
        Add-FixRollbackFailure "보안 정책(secedit) 스냅샷 재적용 실패: $($_.Exception.Message)"
    } finally {
        if ($tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
        Clear-SecEditCache
    }
}

# ---- DBMS(MSSQL) 전용: SQL 기반 원복 (08_dbms) -------------------------------------
# lib/common.sh 의 fix_db_queue_rollback 과 같은 역할 - DB 상태는 파일이 아니라 SQL 실행
# 결과이므로 "원복용 SQL 문 자체"를 백업 위치에 기록해 두고 Restore-FixItem 이 재실행한다.
function Add-FixDbRollback {
    param([Parameter(Mandatory)][string]$Sql)
    $dir = Join-Path (Get-FixItemBackupDir) "dbsql"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $n = 1
    while (Test-Path (Join-Path $dir ("{0:D4}.sql" -f $n))) { $n++ }
    Set-Content -Path (Join-Path $dir ("{0:D4}.sql" -f $n)) -Value $Sql -Encoding UTF8
}

function Restore-FixDbSqlBackup {
    param([Parameter(Mandatory)][string]$Dir)
    $files = Get-ChildItem -Path $Dir -Filter *.sql -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($f in $files) {
        $sql = Get-Content -Raw -Path $f.FullName
        if ($sql.TrimStart().StartsWith("--")) { Add-FixRollbackFailure "SQL 원복 불가(기록만 있음): $($sql.Trim())"; continue }
        Invoke-MssqlQuery -Sql $sql | Out-Null
        if (-not $Global:DbQueryOk) { Add-FixRollbackFailure "SQL 원복 실패: $($sql.Trim())" }
    }
}

# ---- 항목 단위 / 전체 원복 ---------------------------------------------------------
function Restore-FixItem {
    <# 해당 코드가 fix_backup 한 registry/service/acl/share 자원을 전부 원복한다. secedit
       스냅샷은 여기서 건드리지 않는다(위 설명 참고 - Invoke-FixRollbackAll 에서만 처리) #>
    param([Parameter(Mandatory)][string]$Code)
    $Global:FixRollbackCode = $Code
    $dir = Join-Path $Global:FixBackupDir $Code
    # 보안 정책(secedit)은 실행당 스냅샷 1개라 항목 단위로 되돌릴 수 없다 - 예전에는 아무 말 없이 건너뛰고
    # fix.ps1 이 "원복됨"으로 기록했다. 전체 -Rollback 으로만 되돌릴 수 있음을 알린다.
    if (@($Global:FixSecPolicyCodes) -contains $Code) {
        Add-FixRollbackFailure "보안 정책(secedit) 변경은 항목 단위 원복 불가 - '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함"
    }
    if (-not (Test-Path $dir)) { return }
    $noRb = Join-Path $dir "_norollback.txt"
    if (Test-Path -LiteralPath $noRb) {
        Get-Content -Path $noRb -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { Add-FixRollbackFailure "원복 경로 없음: $_" }
    }
    Get-ChildItem -Path (Join-Path $dir "registry") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixRegistryBackup -File $_.FullName }
    Get-ChildItem -Path (Join-Path $dir "service") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixServiceBackup -File $_.FullName }
    Get-ChildItem -Path (Join-Path $dir "acl") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixAclBackup -File $_.FullName }
    Get-ChildItem -Path (Join-Path $dir "share") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixShareBackup -File $_.FullName }
    Get-ChildItem -Path (Join-Path $dir "account") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixLocalAccountBackup -File $_.FullName }
    Get-ChildItem -Path (Join-Path $dir "webconfig") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixWebConfigPropertyBackup -File $_.FullName }
    Get-ChildItem -Path (Join-Path $dir "firewall") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixFirewallProfilesBackup -File $_.FullName }
    $fwRules = Join-Path $dir "firewall\rules-enabled.txt"
    if (Test-Path -LiteralPath $fwRules) {
        Get-Content -Path $fwRules -Encoding UTF8 | Where-Object { $_ } | ForEach-Object {
            try { Disable-NetFirewallRule -Name $_ -ErrorAction Stop }
            catch { Add-FixRollbackFailure "방화벽 규칙 원복 실패 ${_}: $($_.Exception.Message)" }
        }
    }
    Get-ChildItem -Path (Join-Path $dir "remove") -Filter *.origpath.txt -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixPathRemoveBackup -MetaFile $_.FullName }
    Get-ChildItem -Path (Join-Path $dir "apppool") -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { Restore-FixAppPoolIdentityBackup -File $_.FullName }
    $dbsqlDir = Join-Path $dir "dbsql"
    if (Test-Path $dbsqlDir) { Restore-FixDbSqlBackup -Dir $dbsqlDir }
}

function Invoke-FixRollbackAll {
    <# fix.ps1 --rollback <fix-run-dir> 용: 해당 실행의 백업 전체(개별 자원 + secedit 스냅샷)를
       원복한다 #>
    param([Parameter(Mandatory)][string]$RunDir)
    $backupDir = Join-Path $RunDir "backup"
    if (-not (Test-Path $backupDir)) {
        Write-Log "$backupDir 를 찾을 수 없습니다." "ERROR"
        return
    }
    # 다른 컴퓨터에서 만든 백업을 이 컴퓨터에 덮어쓰는 사고 방지(폴더 이름 규칙: <컴퓨터>_<카테고리>_fix_<시각>)
    $rbHost = (Split-Path -Leaf $RunDir) -replace '_\d\d_fix_.*$', ''
    if ($rbHost -ne $env:COMPUTERNAME) {
        Write-Warning "이 백업은 다른 컴퓨터($rbHost)에서 만든 것으로 보입니다(현재: $($env:COMPUTERNAME))."
        if (-not (Read-FixConfirm -Prompt "그래도 이 컴퓨터에 원복하시겠습니까? [y/N]")) { Write-Host "원복하지 않았습니다."; return }
    }
    Write-Warning "원복은 조치 직전 상태로 덮어씁니다. 조치 이후에 사람이 바꾼 설정이 있으면 함께 되돌아갑니다."
    $Global:FixRollbackFailures = @()
    $secPolicyFile = Join-Path $backupDir "_secpolicy\secedit-snapshot.inf"
    if (Test-Path $secPolicyFile) {
        $Global:FixSecPolicyBackupFile = $secPolicyFile
        Restore-FixSecPolicyBackup
        Write-Host "보안 정책(secedit) 스냅샷 전체 원복 시도(결과는 아래 요약 참고)"
    }
    $Global:FixSecPolicyCodes = @()   # 전체 원복에서는 secedit 를 위에서 통째로 되돌리므로 항목별 경고 불필요
    $Global:FixBackupDir = $backupDir
    # 여러 항목이 같은 파일을 순차적으로 수정했을 수 있으므로 적용 역순(코드 내림차순)으로
    # 원복한다 - 정순으로 처리하면 뒤에 적용된 항목의 백업이 마지막에 덮어써 앞 항목의 조치만
    # 남는 버그가 있다(03_web(sh) 쪽 실기 테스트로 실제로 발견해 lib/common.sh 와 함께 수정).
    Get-ChildItem -Path $backupDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "_secpolicy" } |
        Sort-Object Name -Descending |
        ForEach-Object {
            $n = @($Global:FixRollbackFailures).Count
            Restore-FixItem -Code $_.Name
            if (@($Global:FixRollbackFailures).Count -eq $n) { Write-Host "원복 완료: $($_.Name)" }
            else { Write-Host "원복 일부 실패/불가: $($_.Name)" -ForegroundColor Yellow }
        }
    if (@($Global:FixRollbackFailures).Count -gt 0) {
        Write-Host "되돌리지 못한 항목이 있습니다 - 수동 확인 필요:" -ForegroundColor Red
        $Global:FixRollbackFailures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
}

Export-ModuleMember -Function Remove-FixDefaultShares, Write-Log, Get-OsFamily, Show-Banner, Show-Progress, New-PrivateDirectory, New-PrivateTempFile, Invoke-NativeCommand, Invoke-CimCmdletWithTimeout, Get-AclAllowRulesForSids, ConvertTo-SidString, Get-LocalGroupMembersBySid, Get-SecurityCenterProducts, New-OutputDir, Test-IsElevatedAdmin, Get-ServiceChecked, Test-IisInstalled, Test-IsDomainController, Protect-SecretText, Test-IisInstalledButUnreadable,New-CheckResult, Save-ResultJson, New-ReportHtml, Test-RegistryValue, Get-SecEditExport, Clear-SecEditCache, Get-SecPolicyValue, ConvertFrom-Sid, Get-SecPrivilegeAccounts, Get-SecPrivilegeSids, Invoke-MssqlQuery, Test-MssqlPreflight, Test-MssqlRemoteTarget,Test-IisAvailable, Get-IisSiteNames, Get-IisSitePhysicalPath, Get-IisSiteConfigPaths, Get-IisConfigValue, New-FixOutputDir, Get-ResultVulnCodes, Test-FixResultTarget, Test-FixIsAdmin, Test-FixInteractive, Read-FixConfirm, Get-FixRollbackNote, Confirm-FixPlan,Enter-FixLock, Exit-FixLock, Save-FixBackupJson, Get-FixItemBackupDir,Backup-FixRegistryValue, Restore-FixRegistryBackup, Set-FixRegistryValue, Remove-FixRegistryValue, Backup-FixServiceState, Restore-FixServiceBackup, Disable-FixService, Backup-FixLocalAccountState, Restore-FixLocalAccountBackup, Set-FixLocalAccountDisabled, Backup-FixWebConfigProperty, ConvertTo-FixPlainValue, Restore-FixWebConfigPropertyBackup, Set-FixWebConfigProperty, Invoke-FixIisRemoveServerHeader, Invoke-FixIisConfigPaths,Backup-FixFirewallProfiles, Restore-FixFirewallProfilesBackup, Test-FixFirewallPortAllowed, Enable-FixFirewallSafely,Backup-FixPathAndRemove, Restore-FixPathRemoveBackup, Backup-FixAppPoolIdentity, Restore-FixAppPoolIdentityBackup, Set-FixAppPoolIdentity, Add-FixDbRollback, Restore-FixDbSqlBackup, Backup-FixAcl, Restore-FixAclBackup, Remove-FixAclIdentity, Backup-FixShareAccess, Restore-FixShareBackup, Revoke-FixShareEveryone, Backup-FixSecPolicy, Set-FixSecPolicyValue, Set-FixSecPrivilege, Restore-FixSecPolicyBackup, Add-FixRollbackFailure, Register-FixNoRollback, Restore-FixItem, Invoke-FixRollbackAll -Variable ToolVersion, GuideVersion
