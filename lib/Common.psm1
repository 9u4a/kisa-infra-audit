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

function New-OutputDir {
    param([string]$BaseDir, [string]$CategoryNum)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $outDir = Join-Path $BaseDir "$($env:COMPUTERNAME)_${CategoryNum}_$ts"
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "raw") | Out-Null
    $Script:RunLogPath = Join-Path $outDir "run.log"
    New-Item -ItemType File -Force -Path $Script:RunLogPath | Out-Null
    return $outDir
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
    return $sections
}

function Get-SecPolicyValue {
    <# [System Access] 등 단순 key=value 섹션에서 값을 조회. 없으면 $null #>
    param([Parameter(Mandatory)][string]$Section, [Parameter(Mandatory)][string]$Name)
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
    $raw = Get-SecPolicyValue -Section "Privilege Rights" -Name $Right
    if (-not $raw) { return @() }
    return $raw -split ',' | Where-Object { $_ } | ForEach-Object { ConvertFrom-Sid $_.Trim() }
}

# ---- MSSQL 연결/쿼리 (08_dbms) ---------------------------------------------------
# sqlcmd.exe 를 사용한다(MSSQL 설치 시 기본 동봉되는 mssql-tools, 대상 무설치 원칙 준수).
# 비밀번호는 인자로 절대 넘기지 않고 SQLCMDPASSWORD 환경변수로만 전달한다
# (run.ps1 이 $env:DB_PASSWORD 를 이 변수에 매핑, 08_dbms/CLAUDE.md "접속정보 취급" 원칙).
# $Global:DbQueryOk 로 "쿼리 실패"와 "쿼리 성공+결과 0건"을 구분한다(PC-15에서 배운 원칙과 동일).
function Invoke-MssqlQuery {
    param([Parameter(Mandatory)][string]$Sql)
    # -C: 서버 인증서를 신뢰(자체 서명 인증서가 흔한 사내/컨테이너 환경 대응). mssql-tools18(sqlcmd
    # Go 재작성판, 현재 표준 배포판)은 기본적으로 암호화 연결을 강제하며 인증서 검증에 실패하면
    # 접속 자체가 안 되므로 필요하다 (구버전 mssql-tools 의 sqlcmd 는 이 옵션이 없을 수 있음).
    $sqlArgs = @('-h', '-1', '-W', '-s', '|', '-b', '-C')
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
    } catch { return $null }
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
    $Global:FixOutDir = Join-Path $BaseDir "$($env:COMPUTERNAME)_${CategoryNum}_fix_$ts"
    $Global:FixBackupDir = Join-Path $Global:FixOutDir "backup"
    New-Item -ItemType Directory -Force -Path $Global:FixBackupDir | Out-Null
    $Global:FixLog = Join-Path $Global:FixOutDir "changes.log"
    New-Item -ItemType File -Force -Path $Global:FixLog | Out-Null
    $Global:FixSecPolicyBackupFile = $null
    return $Global:FixOutDir
}

function Get-ResultVulnCodes {
    <# result.json(진단 결과)에서 status=VULN 인 코드만 배열로 반환 #>
    param([Parameter(Mandatory)][string]$ResultJson)
    $r = Get-Content -Raw -Encoding UTF8 -Path $ResultJson | ConvertFrom-Json
    return @($r.items | Where-Object { $_.status -eq "VULN" } | ForEach-Object { $_.code })
}

function Get-FixItemBackupDir {
    <# 현재 $Global:FixCode 에 대응하는 백업 디렉터리를 만들고 경로를 반환 #>
    $d = Join-Path $Global:FixBackupDir $Global:FixCode
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}

# ---- 레지스트리 값 백업/설정/원복 -------------------------------------------------
function Backup-FixRegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $dir = Join-Path (Get-FixItemBackupDir) "registry"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $safe = ("$Path--$Name") -replace '[\\:\s]', '_'
    $file = Join-Path $dir "$safe.json"
    $existed = $false; $value = $null; $kind = $null
    if (Test-Path -LiteralPath $Path) {
        try {
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            if ($item.GetValueNames() -contains $Name) {
                $existed = $true
                $value = $item.GetValue($Name)
                $kind = $item.GetValueKind($Name).ToString()
            }
        } catch { }
    }
    [PSCustomObject]@{ Path = $Path; Name = $Name; Existed = $existed; Value = $value; Kind = $kind } |
        ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Restore-FixRegistryBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    try {
        if ($o.Existed) {
            if (-not (Test-Path -LiteralPath $o.Path)) { New-Item -Path $o.Path -Force | Out-Null }
            New-ItemProperty -Path $o.Path -Name $o.Name -PropertyType $o.Kind -Value $o.Value -Force | Out-Null
        } elseif (Test-Path -LiteralPath $o.Path) {
            Remove-ItemProperty -Path $o.Path -Name $o.Name -ErrorAction SilentlyContinue
        }
    } catch { }
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
    $dir = Join-Path (Get-FixItemBackupDir) "service"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir "$Name.json"
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    $found = [bool]$svc
    $startType = if ($svc) { $svc.StartType.ToString() } else { $null }
    $status = if ($svc) { $svc.Status.ToString() } else { $null }
    [PSCustomObject]@{ Name = $Name; Found = $found; StartType = $startType; Status = $status } |
        ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Restore-FixServiceBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    if (-not $o.Found) { return }
    try {
        Set-Service -Name $o.Name -StartupType $o.StartType -ErrorAction SilentlyContinue
        if ($o.Status -eq "Running") { Start-Service -Name $o.Name -ErrorAction SilentlyContinue }
    } catch { }
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
    $dir = Join-Path (Get-FixItemBackupDir) "account"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir "$Name.json"
    $u = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    $enabled = if ($u) { $u.Enabled } else { $null }
    [PSCustomObject]@{ Name = $Name; Found = [bool]$u; Enabled = $enabled } |
        ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Restore-FixLocalAccountBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    if (-not $o.Found) { return }
    try {
        if ($o.Enabled) { Enable-LocalUser -Name $o.Name -ErrorAction SilentlyContinue }
        else { Disable-LocalUser -Name $o.Name -ErrorAction SilentlyContinue }
    } catch { }
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

# ---- IIS/FTP 서버 설정(WebAdministration) 값 백업/설정/원복 ------------------------
# W-23(FTP 익명 인증) 등 레지스트리가 아니라 applicationHost.config 기반 설정을 바꾸는 소수
# 항목 전용. 03_web(IIS)의 Get-IisConfigValue 와 달리 여기서는 값을 직접 바꿔야 하므로 별도
# Set-/Backup-/Restore- 세트를 둔다(모듈 재사용 범위: 03_web IIS 웹사이트 설정과 Windows FTP
# 서버 설정은 PSPath 필터만 다를 뿐 같은 WebAdministration 공급자를 쓴다).
function Backup-FixWebConfigProperty {
    param([Parameter(Mandatory)][string]$Filter, [Parameter(Mandatory)][string]$Name, [string]$PSPath = "IIS:\")
    $dir = Join-Path (Get-FixItemBackupDir) "webconfig"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $safe = ("$PSPath--$Filter--$Name") -replace '[\\:/\s]', '_'
    $file = Join-Path $dir "$safe.json"
    try {
        $v = Get-WebConfigurationProperty -Filter $Filter -Name $Name -PSPath $PSPath -ErrorAction Stop
        $value = if ($v.PSObject.Properties.Name -contains "Value") { $v.Value } else { $v }
    } catch { $value = $null }
    [PSCustomObject]@{ Filter = $Filter; Name = $Name; PSPath = $PSPath; Value = $value } |
        ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Restore-FixWebConfigPropertyBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    try {
        Set-WebConfigurationProperty -Filter $o.Filter -Name $o.Name -Value $o.Value -PSPath $o.PSPath -ErrorAction SilentlyContinue
    } catch { }
}

function Set-FixWebConfigProperty {
    param(
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$PSPath = "IIS:\"
    )
    Backup-FixWebConfigProperty -Filter $Filter -Name $Name -PSPath $PSPath | Out-Null
    try {
        Set-WebConfigurationProperty -Filter $Filter -Name $Name -Value $Value -PSPath $PSPath -ErrorAction Stop
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "$PSPath [$Filter] $Name = $Value 로 설정함"
        $Global:FixEvidence = ""
    } catch {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "$PSPath [$Filter] $Name 설정 실패: $($_.Exception.Message)"
        $Global:FixEvidence = ""
    }
}

# ---- 방화벽 프로필 상태 백업/원복 (W-64/PC-15) -------------------------------------
function Backup-FixFirewallProfiles {
    $dir = Join-Path (Get-FixItemBackupDir) "firewall"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir "profiles.json"
    $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled)
    $profiles | ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Restore-FixFirewallProfilesBackup {
    param([Parameter(Mandatory)][string]$File)
    $items = @(Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json)
    foreach ($p in $items) {
        try { Set-NetFirewallProfile -Name $p.Name -Enabled $p.Enabled -ErrorAction SilentlyContinue } catch { }
    }
}

# ---- NTFS ACL 백업/원복 ------------------------------------------------------------
function Backup-FixAcl {
    param([Parameter(Mandatory)][string]$Path)
    $dir = Join-Path (Get-FixItemBackupDir) "acl"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $safe = ($Path -replace '[\\:]', '_')
    $file = Join-Path $dir "$safe.json"
    $acl = Get-Acl -Path $Path
    [PSCustomObject]@{ Path = $Path; Sddl = $acl.Sddl } | ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Restore-FixAclBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    try {
        $acl = Get-Acl -Path $o.Path
        $acl.SetSecurityDescriptorSddlForm($o.Sddl)
        Set-Acl -Path $o.Path -AclObject $acl
    } catch { }
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
    $dir = Join-Path (Get-FixItemBackupDir) "share"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir "$ShareName.json"
    $access = @(Get-SmbShareAccess -Name $ShareName -ErrorAction SilentlyContinue |
        Select-Object AccountName, AccessControlType, AccessRight)
    [PSCustomObject]@{ ShareName = $ShareName; Access = $access } |
        ConvertTo-Json -Depth 4 | Set-Content -Path $file -Encoding UTF8
    return $file
}

function Restore-FixShareBackup {
    param([Parameter(Mandatory)][string]$File)
    $o = Get-Content -Raw -Encoding UTF8 -Path $File | ConvertFrom-Json
    foreach ($a in @($o.Access)) {
        try {
            Grant-SmbShareAccess -Name $o.ShareName -AccountName $a.AccountName -AccessRight $a.AccessRight -Force -ErrorAction SilentlyContinue | Out-Null
        } catch { }
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
    $Global:FixSecPolicyBackupFile = Join-Path $dir "secedit-snapshot.inf"
    secedit /export /cfg $Global:FixSecPolicyBackupFile /quiet | Out-Null
    return $Global:FixSecPolicyBackupFile
}

function Set-FixSecPolicyValue {
    <# $Section 예: "System Access" / "Privilege Rights" / "Kerberos Policy".
       $Values 는 그 섹션에 적용할 key=value 해시테이블(여러 개 가능) #>
    param([Parameter(Mandatory)][string]$Section, [Parameter(Mandatory)][hashtable]$Values)
    Backup-FixSecPolicy | Out-Null
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
    Remove-Item -Path $db -Force -ErrorAction SilentlyContinue
}

# ---- 항목 단위 / 전체 원복 ---------------------------------------------------------
function Restore-FixItem {
    <# 해당 코드가 fix_backup 한 registry/service/acl/share 자원을 전부 원복한다. secedit
       스냅샷은 여기서 건드리지 않는다(위 설명 참고 - Invoke-FixRollbackAll 에서만 처리) #>
    param([Parameter(Mandatory)][string]$Code)
    $dir = Join-Path $Global:FixBackupDir $Code
    if (-not (Test-Path $dir)) { return }
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
    $secPolicyFile = Join-Path $backupDir "_secpolicy\secedit-snapshot.inf"
    if (Test-Path $secPolicyFile) {
        $Global:FixSecPolicyBackupFile = $secPolicyFile
        Restore-FixSecPolicyBackup
        Write-Host "보안 정책(secedit) 스냅샷 전체 원복 완료"
    }
    $Global:FixBackupDir = $backupDir
    # 여러 항목이 같은 파일을 순차적으로 수정했을 수 있으므로 적용 역순(코드 내림차순)으로
    # 원복한다 - 정순으로 처리하면 뒤에 적용된 항목의 백업이 마지막에 덮어써 앞 항목의 조치만
    # 남는 버그가 있다(03_web(sh) 쪽 실기 테스트로 실제로 발견해 lib/common.sh 와 함께 수정).
    Get-ChildItem -Path $backupDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "_secpolicy" } |
        Sort-Object Name -Descending |
        ForEach-Object {
            Restore-FixItem -Code $_.Name
            Write-Host "원복 완료: $($_.Name)"
        }
}

Export-ModuleMember -Function Write-Log, Get-OsFamily, Show-Banner, Show-Progress, New-OutputDir, New-CheckResult, Save-ResultJson, New-ReportHtml, Test-RegistryValue, Get-SecEditExport, Get-SecPolicyValue, ConvertFrom-Sid, Get-SecPrivilegeAccounts, Invoke-MssqlQuery, Test-IisAvailable, Get-IisSiteNames, Get-IisSitePhysicalPath, Get-IisConfigValue, New-FixOutputDir, Get-ResultVulnCodes, Get-FixItemBackupDir, Backup-FixRegistryValue, Restore-FixRegistryBackup, Set-FixRegistryValue, Remove-FixRegistryValue, Backup-FixServiceState, Restore-FixServiceBackup, Disable-FixService, Backup-FixLocalAccountState, Restore-FixLocalAccountBackup, Set-FixLocalAccountDisabled, Backup-FixWebConfigProperty, Restore-FixWebConfigPropertyBackup, Set-FixWebConfigProperty, Backup-FixFirewallProfiles, Restore-FixFirewallProfilesBackup, Backup-FixAcl, Restore-FixAclBackup, Remove-FixAclIdentity, Backup-FixShareAccess, Restore-FixShareBackup, Revoke-FixShareEveryone, Backup-FixSecPolicy, Set-FixSecPolicyValue, Set-FixSecPrivilege, Restore-FixSecPolicyBackup, Restore-FixItem, Invoke-FixRollbackAll -Variable ToolVersion, GuideVersion
