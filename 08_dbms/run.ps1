# 08_dbms/run.ps1 — MSSQL 진단 진입점 (PowerShell 5.1 호환)
#
# 옵션 문자는 전 카테고리와 통일한다: -l(목록) -i(항목) -g(분류) -o(출력) -h(도움말).
# MSSQL은 단일 엔진이라 -e 는 생략한다 (루트 CLAUDE.md "CLI 옵션 문자 통일" 참고).
# 접속 정보는 -SqlHost/-SqlPort/-SqlUser/-SqlDb 로 지정한다. 비밀번호는 인자로 절대 넘기지
# 않고 DB_PASSWORD 환경변수로만 전달한다(내부적으로 SQLCMDPASSWORD 로 매핑, sqlcmd 표준 방식).
#
# 사용법:
#   .\run.ps1                              로컬(Windows 통합 인증)로 전체 항목 진단
#   .\run.ps1 -SqlUser sa -SqlHost .        SQL 인증으로 접속 ($env:DB_PASSWORD 필요)
#   .\run.ps1 -i D-01,D-23                  개별(복수) 항목만 진단
#   .\run.ps1 -g 1                          하위분류 단위 진단
#   .\run.ps1 -l                            항목 목록만 출력 (26항목 전체)
#
# Unix 계열 엔진(MySQL/PostgreSQL/Oracle)은 08_dbms/run.sh 를 사용한다.
# 이 스크립트는 대상 시스템 설정을 변경하지 않는다 (진단 전용).

[CmdletBinding()]
param(
    [Alias("i")][string]$Items = "",
    [Alias("g")][string]$Group = "",
    [Alias("l")][switch]$ListOnly,
    [Alias("o")][string]$OutBase = "",
    [Alias("h")][switch]$Help,
    [string]$SqlHost = "",
    [string]$SqlPort = "",
    [string]$SqlUser = "",
    [string]$SqlDb = ""
)

if ($Help) {
    Write-Host "사용법:"
    Write-Host "  .\run.ps1                              로컬(Windows 통합 인증)로 전체 항목 진단"
    Write-Host "  .\run.ps1 -SqlUser sa -SqlHost .        SQL 인증으로 접속 (`$env:DB_PASSWORD 필요)"
    Write-Host "  .\run.ps1 -i D-01,D-23                  개별(복수) 항목만 진단"
    Write-Host "  .\run.ps1 -g 1                          하위분류 단위 진단"
    Write-Host "  .\run.ps1 -l                            항목 목록만 출력"
    exit 0
}

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path (Split-Path -Parent $ScriptDir) "lib"
$GuideJsonPath = Join-Path $ScriptDir "guide.json"
$CategoryNum = "08"
$CategoryName = "DBMS"
$DbmsEngine = "mssql"

Import-Module (Join-Path $LibDir "Common.psm1") -Force

# checks/*.ps1 의 WMI/CIM 조회 시간 제한(운영 안전 기준 S2). 스크립트 범위라 사용자 세션 기본값은 건드리지 않는다.
$PSDefaultParameterValues = @{ 'Get-CimInstance:OperationTimeoutSec' = 30 }

if (-not (Test-Path $GuideJsonPath)) {
    Write-Error "오류: $GuideJsonPath 가 없습니다. lib/extract_guide.py 를 먼저 실행하세요."
    exit 2
}
$Guide = Get-Content -Raw -Encoding UTF8 -Path $GuideJsonPath | ConvertFrom-Json
$GuideByCode = @{}
foreach ($it in $Guide.items) { $GuideByCode[$it.code] = $it }

if ($ListOnly) {
    "{0,-8} {1,-4} {2,-4} {3}" -f "코드", "중요도", "분류", "항목명" | Write-Output
    foreach ($it in $Guide.items) {
        "{0,-8} {1,-4} {2,-4} {3}" -f $it.code, $it.severity, $it.group_no, $it.title | Write-Output
    }
    exit 0
}

# ---- 대상 코드 선정 ----------------------------------------------------------
if ($Items) {
    $Selected = $Items -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
} elseif ($Group) {
    $Selected = $Guide.items | Where-Object { "$($_.group_no)" -eq $Group } | ForEach-Object { $_.code }
} else {
    $Selected = $Guide.items | ForEach-Object { $_.code }
}

if (-not $Selected -or $Selected.Count -eq 0) {
    Write-Error "대상 항목이 없습니다."
    exit 2
}

# ---- 접속 정보를 환경변수로 매핑 (checks/*.ps1 이 Invoke-MssqlQuery 를 통해 사용) --------
# 이 스크립트를 ". .\run.ps1" 또는 같은 콘솔에서 실행해도 비밀번호가 세션에 남지 않도록,
# 종료(정상/예외/Ctrl+C) 시 finally 에서 실행 전 값으로 되돌린다.
$EnvNames = @('DB_HOST', 'DB_PORT', 'DB_USER', 'DB_NAME', 'SQLCMDPASSWORD')
$EnvBefore = @{}
foreach ($n in $EnvNames) { $EnvBefore[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }

if ($SqlHost) { $env:DB_HOST = $SqlHost }
if ($SqlPort) { $env:DB_PORT = $SqlPort }
if ($SqlUser) { $env:DB_USER = $SqlUser }
if ($SqlDb)   { $env:DB_NAME = $SqlDb }

# SQL 인증인데 비밀번호가 없으면 sqlcmd 가 대화형으로 비밀번호를 묻는다 - audit.ps1 자식 프로세스
# 에서는 화면에 보이지 않은 채 멈추고, 빈 Enter 가 로그인 실패로 누적될 수 있으므로 시작 전에 끝낸다.
if ($env:DB_USER -and -not $env:DB_PASSWORD) {
    foreach ($n in $EnvNames) { [Environment]::SetEnvironmentVariable($n, $EnvBefore[$n], 'Process') }
    Write-Error "SQL 인증(-SqlUser/DB_USER) 사용 시 `$env:DB_PASSWORD 가 필요합니다. Windows 통합 인증은 -SqlUser 를 생략하세요."
    exit 2
}
if ($env:DB_PASSWORD) { $env:SQLCMDPASSWORD = $env:DB_PASSWORD }

# $env:TEMP 는 Windows 전용이라 Linux(pwsh 7, MSSQL Linux 호스트)에서는 비어 있다 -
# [System.IO.Path]::GetTempPath() 는 두 플랫폼 모두에서 동작한다.
$Global:DbErrFile = Join-Path ([System.IO.Path]::GetTempPath()) "kisa-dbms-err-$PID.txt"
$Global:DbConnFailed = $false

try {
    if (-not $OutBase) { $OutBase = Join-Path (Split-Path -Parent $ScriptDir) "output" }
    $OutDir = New-OutputDir -BaseDir $OutBase -CategoryNum $CategoryNum

    Show-Banner -Category $CategoryName -Total $Selected.Count -OsFamily $DbmsEngine
    Write-Log "진단 시작: 엔진=$DbmsEngine 대상=$($Selected.Count)항목"

    # 접속을 항목마다 시도하기 전에 1회만 시험한다 - 실패하면 이후 DB 조회 항목은 접속 없이 ERROR.
    # sysadmin 이 아니면 카탈로그 일부만 보여(D-03 은 자기 로그인만, D-11/24 는 권한 일부만, D-26 은
    # 감사 목록이 비어 보임) 거짓 GOOD/VULN 이 난다 - 이 항목들은 ERROR 로 바꾼다.
    $SysadminOnly = @("D-03", "D-11", "D-24", "D-26")
    $NotSysadmin = $false
    if (Test-MssqlPreflight) {
        Write-Host "DB 접속    : 사전 점검 성공"
        Write-Log "DB 접속 사전 점검 성공"
        $sa = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT IS_SRVROLEMEMBER('sysadmin');"
        if ($Global:DbQueryOk -and "$(@($sa)[0])".Trim() -ne "1") {
            $NotSysadmin = $true
            Write-Warning "접속 계정이 sysadmin 이 아닙니다 - $($SysadminOnly -join ', ') 는 전체 정보를 볼 수 없어 ERROR 로 표시합니다."
        }
    } else {
        Write-Warning "DB 접속 사전 점검 실패 - 계정 잠금 방지를 위해 재시도하지 않고 DB 조회 항목은 ERROR 로 처리합니다: $Global:DbConnFailMsg"
        Write-Log "DB 접속 사전 점검 실패(재시도 안 함): $Global:DbConnFailMsg" "WARN"
    }

    $Results = @()
    $CsvRows = @()
    $n = 0
    # 중단(Ctrl+C·예외)돼도 그때까지 진단한 항목을 result.partial.json 으로 남긴다(운영 안전 기준 S7) -
    # 예전에는 결과를 루프가 끝난 뒤 한 번만 저장해 중단되면 run.log/raw 만 남았다.
    $runCompleted = $false
    try {
    foreach ($code in $Selected) {
        $n++
        $meta = $GuideByCode[$code]
        $title = if ($meta) { $meta.title } else { $code }
        $checkFile = Join-Path $ScriptDir "checks\mssql\$code.ps1"

        if (Test-Path $checkFile) {
            try {
                $r = & $checkFile
                if (-not $r) {
                    $r = New-CheckResult -Code $code -Status "ERROR" -Detail "check 스크립트가 결과를 반환하지 않음"
                }
            } catch {
                $r = New-CheckResult -Code $code -Status "ERROR" -Detail "check 실행 중 예외 발생: $($_.Exception.Message)"
            }
        } else {
            $r = New-CheckResult -Code $code -Status "NA" -Detail "이 항목은 MSSQL 대상이 아니거나 아직 구현되지 않음"
        }
        if ($NotSysadmin -and $SysadminOnly -contains $code -and $r.status -in @("GOOD", "VULN")) {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "접속 계정이 sysadmin 이 아니라 전체 정보를 볼 수 없어 판정 불가(일부만 보고 내린 판정: $($r.status))" -Evidence $r.evidence
        }

        Show-Progress -Current $n -Total $Selected.Count -Code $code -Title $title -Status $r.status
        Write-Log "$code [$($r.status)] $($r.detail)"
        $Results += $r
        if ($r.evidence) {
            $r.evidence | Out-File -FilePath (Join-Path $OutDir "raw\$code.txt") -Encoding utf8
        }
        $CsvRows += [PSCustomObject]@{
            code = $code; severity = $(if ($meta) { $meta.severity } else { "" })
            group = $(if ($meta) { $meta.group_no } else { "" }); title = $title
            status = $r.status; detail = $r.detail
        }
    }

    $runCompleted = $true
    } finally {
        if (-not $runCompleted -and @($Results).Count -gt 0) {
            Save-ResultJson -Results $Results -OutFile (Join-Path $OutDir "result.partial.json") -Category $CategoryName -OsFamily $DbmsEngine
            Write-Warning "중단됨 - 지금까지 진단한 $(@($Results).Count)개 항목을 $(Join-Path $OutDir 'result.partial.json') 에 저장했습니다."
        }
    }
    $ResultJson = Join-Path $OutDir "result.json"
    Save-ResultJson -Results $Results -OutFile $ResultJson -Category $CategoryName -OsFamily $DbmsEngine
    $CsvRows | Export-Csv -Path (Join-Path $OutDir "result.csv") -NoTypeInformation -Encoding UTF8

    New-ReportHtml -LibDir $LibDir -GuideJson $GuideJsonPath -ResultJson $ResultJson -OutHtml (Join-Path $OutDir "report.html")

    $counts = @{ VULN = 0; MANUAL = 0; ERROR = 0; NA = 0; GOOD = 0 }
    foreach ($r in $Results) { $counts[$r.status]++ }
    $base = $counts.VULN + $counts.GOOD
    $rate = if ($base -gt 0) { [int](($counts.GOOD * 100) / $base) } else { 0 }

    $summary = @"
=== $CategoryName 진단 요약 ===
호스트   : $env:COMPUTERNAME
환경     : $DbmsEngine
시각     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
총 항목  : $($Results.Count)
----------------------------
취약         $($counts.VULN)
수동점검     $($counts.MANUAL)
오류         $($counts.ERROR)
해당없음     $($counts.NA)
양호         $($counts.GOOD)
----------------------------
준수율(취약/양호 중): $rate%
"@
    $summary | Out-File -FilePath (Join-Path $OutDir "summary.txt") -Encoding utf8

    Write-Host "----------------------------------------------------------------------"
    Write-Host $summary
    Write-Host "----------------------------------------------------------------------"
    Write-Host "결과 경로: $OutDir"
    Write-Host "  - result.json / result.csv  (기계 판독·표계산용)"
    Write-Host "  - report.html                (브라우저로 열람)"
    Write-Host "  - summary.txt / run.log      (요약 · 실행 로그)"
} finally {
    Remove-Item -Path $Global:DbErrFile -Force -ErrorAction SilentlyContinue
    foreach ($n in $EnvNames) { [Environment]::SetEnvironmentVariable($n, $EnvBefore[$n], 'Process') }
    $Global:DbConnFailed = $false
}
