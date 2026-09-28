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

Export-ModuleMember -Function Write-Log, Get-OsFamily, Show-Banner, Show-Progress, New-OutputDir, New-CheckResult, Save-ResultJson, New-ReportHtml, Test-RegistryValue, Get-SecEditExport, Get-SecPolicyValue, ConvertFrom-Sid, Get-SecPrivilegeAccounts, Invoke-MssqlQuery -Variable ToolVersion, GuideVersion
