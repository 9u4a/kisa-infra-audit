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
        Write-Warning "결과 폴더 접근 권한을 제한하지 못함($Path): $($_.Exception.Message)"
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

function Test-IsDomainController {
    <# DomainRole 4/5 = 백업/주 도메인 컨트롤러. DC 에는 로컬 SAM 이 없어 Win32_UserAccount 조회가 도메인
       전체 계정 열거(LDAP 대량 조회)가 될 수 있으므로 계정 열거형 check 는 DC 에서 건너뛴다 #>
    if ($null -ne $Global:IsDcCache) { return $Global:IsDcCache }
    try { $Global:IsDcCache = ((Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 30 -ErrorAction Stop).DomainRole -ge 4) }
    catch { $Global:IsDcCache = $false }
    return $Global:IsDcCache
}

function Protect-SecretText {
    <# 명령줄 등 자유 텍스트에서 흔한 자격증명 패턴의 값을 *** 로 가린다(증적 저장 전 적용).
       예) "net use \\s\c /user:dom\u P@ss" / "app.exe -password x" / "pwd=x;" / ConvertTo-SecureString "x" #>
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text
    $t = $t -replace '(?i)((?:^|\s)[-/](?:p|pw|pwd|pass|passwd|password)(?:\s+|[:=]))(?![-/])("[^"]*"|''[^'']*''|\S+)', '$1***'
    $t = $t -replace '(?i)((?:password|passwd|pwd|secret|token|apikey|api_key)\s*[=:]\s*)("[^"]*"|''[^'']*''|[^\s;&]+)', '$1***'
    $t = $t -replace '(?i)(/user:\S+\s+)(?![-/])(\S+)', '$1***'
    $t = $t -replace '(?i)(ConvertTo-SecureString\s+(?:-String\s+)?)("[^"]*"|''[^'']*'')', '$1***'
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
    $sorted = $Results | Sort-Object @{Expression={$StatusOrder[$_.status]}}, code
    $obj = [ordered]@{
        tool_version  = $Script:ToolVersion
        guide_version = $Script:GuideVersion
        category      = $Category
        host          = $env:COMPUTERNAME
        env           = $OsFamily
        generated_at  = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
        items         = $sorted
    }
    $obj | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutFile -Encoding utf8
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
        return $null
    }
}

# ---- secedit 기반 로컬 보안 정책 조회 ---------------------------------------------
# secedit /export 결과([System Access], [Privilege Rights] 등)를 1회만 내보내 캐시한다.
# 비밀번호/계정 잠금 정책, 사용자 권한 할당(User Rights Assignment)처럼 단순 레지스트리 값이
# 아닌 정책은 이 방법으로만 조회 가능하다 (SAM/LSA 정책 객체이기 때문).
function Get-SecEditExport {
    if ($Script:SecEditCache) { return $Script:SecEditCache }

    $tmp = Join-Path $env:TEMP "kisa-secedit-$PID.inf"
    $sections = @{}
    try {
        secedit /export /cfg $tmp /quiet | Out-Null
        if (Test-Path $tmp) {
            $current = $null
            foreach ($line in Get-Content -Path $tmp -Encoding Unicode) {
                $t = $line.Trim()
                if ($t -match '^\[(.+)\]$') {
                    $current = $Matches[1]
                    $sections[$current] = @{}
                } elseif ($current -and $t -match '^([^=]+?)\s*=\s*(.*)$') {
                    $sections[$current][$Matches[1].Trim()] = $Matches[2].Trim()
                }
            }
        }
    } catch {
        Write-Log "secedit /export 실행 실패: $_" "WARN"
    } finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
    $Script:SecEditCache = $sections
    # 내보내기 실패(관리자 권한 없음 등)면 모든 정책 값이 $null 로 보여 "미설정 = 취약/양호"로 오판된다.
    # 02_windows/07_pc run.ps1 이 이 플래그로 해당 항목의 GOOD/VULN 을 ERROR 로 바꾼다.
    $Global:SecEditFailed = ($sections.Count -eq 0)
    return $sections
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
    # -C: 서버 인증서를 신뢰(자체 서명 인증서가 흔한 사내/컨테이너 환경 대응). mssql-tools18(sqlcmd
    # Go 재작성판, 현재 표준 배포판)은 기본적으로 암호화 연결을 강제하며 인증서 검증에 실패하면
    # 접속 자체가 안 되므로 필요하다 (구버전 mssql-tools 의 sqlcmd 는 이 옵션이 없을 수 있음).
    $sqlArgs = @('-h', '-1', '-W', '-s', '|', '-b', '-C', '-l', '5', '-t', '60')
    $target = if ($env:DB_HOST) { $env:DB_HOST } else { 'localhost' }
    if ($env:DB_PORT) { $target = "$target,$($env:DB_PORT)" }
    $sqlArgs += @('-S', $target)
    if ($env:DB_USER) { $sqlArgs += @('-U', $env:DB_USER) } else { $sqlArgs += @('-E') }
    if ($env:DB_NAME) { $sqlArgs += @('-d', $env:DB_NAME) }
    $sqlArgs += @('-Q', $Sql)
    try {
        $out = & sqlcmd @sqlArgs 2>$Global:DbErrFile
        $Global:DbQueryOk = ($LASTEXITCODE -eq 0)
        return $out
    } catch {
        $Global:DbQueryOk = $false
        $_.Exception.Message | Out-File -FilePath $Global:DbErrFile -Encoding utf8
        return $null
    }
}

function Test-MssqlPreflight {
    <# 접속을 1회 시험. 실패하면 $Global:DbConnFailed/$Global:DbConnFailMsg 를 세우고 $false 반환 #>
    $Global:DbConnFailed = $false
    $Global:DbConnFailMsg = ""
    $null = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT 1;"
    if ($Global:DbQueryOk) { return $true }
    $msg = if (Test-Path $Global:DbErrFile) { (Get-Content -Path $Global:DbErrFile -TotalCount 2) -join " " } else { "" }
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
    return [bool](Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue)
}

function Get-IisSiteNames {
    <# 구성된 사이트 이름 목록 (IIS 미설치/사이트 없음이면 빈 배열) #>
    if (-not (Test-IisAvailable)) { return @() }
    try { return @(Get-Website -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { return @() }
}

function Get-IisSitePhysicalPath {
    <# 사이트의 실제 경로(환경변수 展開 완료). 조회 실패 시 $null #>
    param([Parameter(Mandatory)][string]$SiteName)
    try {
        $p = (Get-Website -Name $SiteName -ErrorAction Stop).physicalPath
        if (-not $p) { return $null }
        return [System.Environment]::ExpandEnvironmentVariables($p)
    } catch { return $null }
}

function Get-IisConfigValue {
    <# Get-WebConfigurationProperty 래퍼 - 사이트 지정 시 IIS:\Sites\<site>, 미지정 시 서버 전체
       기본값(MACHINE/WEBROOT/APPHOST)에서 설정값을 조회. 속성이 없거나 조회 실패 시 $null #>
    param(
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Name,
        [string]$SiteName = ""
    )
    try {
        if ($SiteName) {
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
        $Global:IisConfigQueryError = "$Filter/@$Name$(if ($SiteName) { " ($SiteName)" }): $($_.Exception.Message)"
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
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Restore-FixPathRemoveBackup {
    param([Parameter(Mandatory)][string]$MetaFile)
    $orig = (Get-Content -Raw -Path $MetaFile).Trim()
    $src = $MetaFile -replace '\.origpath\.txt$', ''
    if (-not (Test-Path -LiteralPath $src)) { return }
    $parent = Split-Path -Parent $orig
    try {
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent -ErrorAction Stop | Out-Null }
        Copy-Item -LiteralPath $src -Destination $orig -Recurse -Force -ErrorAction Stop
    } catch { Add-FixRollbackFailure "삭제된 경로 복원 실패 ${orig}: $($_.Exception.Message)" }
}

# ---- IIS 애플리케이션 풀 identity 백업/설정/원복 (WEB-09) --------------------------
function Backup-FixAppPoolIdentity {
    param([Parameter(Mandatory)][string]$PoolName)
    $dir = Get-FixItemBackupDir -Sub "apppool"
    $file = Join-Path $dir "$PoolName.json"
    if (Test-Path -LiteralPath $file) { return $file }
    try { $current = (Get-ItemProperty "IIS:\AppPools\$PoolName" -Name processModel.identityType -ErrorAction Stop).Value }
    catch { throw "[백업 실패] 애플리케이션 풀 '$PoolName' 현재 identity 를 읽을 수 없음: $($_.Exception.Message)" }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ PoolName = $PoolName; IdentityType = "$current" }))
}

function Restore-FixAppPoolIdentityBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    if (-not $o.IdentityType) { return }
    try { Set-ItemProperty "IIS:\AppPools\$($o.PoolName)" -Name processModel.identityType -Value $o.IdentityType -ErrorAction Stop }
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
    $safe = ("$PSPath--$Location--$Filter--$Name") -replace '[\:/\s\[\]@=''"*?<>|]', '_'
    $file = Join-Path $dir "$safe.json"
    if (Test-Path -LiteralPath $file) { return $file }
    $loc = @{}; if ($Location) { $loc.Location = $Location }
    # 읽기 실패를 $null 로 기록하면 원복 때 설정을 빈 값으로 덮어쓰므로 중단한다.
    try {
        $v = Get-WebConfigurationProperty -Filter $Filter -Name $Name -PSPath $PSPath @loc -ErrorAction Stop
        $value = if ($v.PSObject.Properties.Name -contains "Value") { $v.Value } else { $v }
    } catch { throw "[백업 실패] IIS 설정 현재 값을 읽을 수 없음($PSPath $Location [$Filter] $Name): $($_.Exception.Message)" }
    return (Save-FixBackupJson -File $file -Object ([PSCustomObject]@{ Filter = $Filter; Name = $Name; PSPath = $PSPath; Location = $Location; Value = $value }))
}

function Restore-FixWebConfigPropertyBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    $loc = @{}; if ($o.Location) { $loc.Location = $o.Location }
    try {
        Set-WebConfigurationProperty -Filter $o.Filter -Name $o.Name -Value $o.Value -PSPath $o.PSPath @loc -ErrorAction Stop
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
    if ($PSPath -notmatch '^IIS:\Sites\(.+)$') { return }
    $site = $Matches[1]
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
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "kisa-secedit-apply-$PID.inf"
    $lines = @("[Unicode]", "Unicode=yes", "[$Section]")
    foreach ($k in $Values.Keys) { $lines += "$k = $($Values[$k])" }
    $lines += @("[Version]", 'signature="$CHICAGO$"', "Revision=1")
    Set-Content -Path $tmp -Value $lines -Encoding Unicode
    $db = Join-Path ([System.IO.Path]::GetTempPath()) "kisa-secedit-apply-$PID.sdb"
    $area = if ($Section -eq "Privilege Rights") { "USER_RIGHTS" } else { "SECURITYPOLICY" }
    $out = & secedit /configure /db $db /cfg $tmp /areas $area /quiet 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    Remove-Item -Path $tmp, $db -Force -ErrorAction SilentlyContinue
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
    $db = Join-Path ([System.IO.Path]::GetTempPath()) "kisa-secedit-rollback-$PID.sdb"
    & secedit /configure /db $db /cfg $Global:FixSecPolicyBackupFile /areas SECURITYPOLICY, USER_RIGHTS /quiet | Out-Null
    if ($LASTEXITCODE -ne 0) { Add-FixRollbackFailure "보안 정책(secedit) 스냅샷 재적용 실패(exit=$LASTEXITCODE)" }
    Remove-Item -Path $db -Force -ErrorAction SilentlyContinue
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

Export-ModuleMember -Function Write-Log, Get-OsFamily, Show-Banner, Show-Progress, New-PrivateDirectory, New-OutputDir, Test-IsDomainController, Protect-SecretText, Test-IisInstalledButUnreadable,New-CheckResult, Save-ResultJson, New-ReportHtml, Test-RegistryValue, Get-SecEditExport, Get-SecPolicyValue, ConvertFrom-Sid, Get-SecPrivilegeAccounts, Invoke-MssqlQuery, Test-MssqlPreflight,Test-IisAvailable, Get-IisSiteNames, Get-IisSitePhysicalPath, Get-IisConfigValue, New-FixOutputDir, Get-ResultVulnCodes, Test-FixIsAdmin, Test-FixInteractive, Read-FixConfirm, Get-FixRollbackNote, Confirm-FixPlan,Enter-FixLock, Exit-FixLock, Save-FixBackupJson, Get-FixItemBackupDir,Backup-FixRegistryValue, Restore-FixRegistryBackup, Set-FixRegistryValue, Remove-FixRegistryValue, Backup-FixServiceState, Restore-FixServiceBackup, Disable-FixService, Backup-FixLocalAccountState, Restore-FixLocalAccountBackup, Set-FixLocalAccountDisabled, Backup-FixWebConfigProperty, Restore-FixWebConfigPropertyBackup, Set-FixWebConfigProperty, Backup-FixFirewallProfiles, Restore-FixFirewallProfilesBackup, Test-FixFirewallPortAllowed, Enable-FixFirewallSafely,Backup-FixPathAndRemove, Restore-FixPathRemoveBackup, Backup-FixAppPoolIdentity, Restore-FixAppPoolIdentityBackup, Set-FixAppPoolIdentity, Add-FixDbRollback, Restore-FixDbSqlBackup, Backup-FixAcl, Restore-FixAclBackup, Remove-FixAclIdentity, Backup-FixShareAccess, Restore-FixShareBackup, Revoke-FixShareEveryone, Backup-FixSecPolicy, Set-FixSecPolicyValue, Set-FixSecPrivilege, Restore-FixSecPolicyBackup, Add-FixRollbackFailure, Register-FixNoRollback, Restore-FixItem, Invoke-FixRollbackAll -Variable ToolVersion, GuideVersion
