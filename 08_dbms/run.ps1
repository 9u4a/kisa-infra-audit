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

# ---- 접속 정보를 환경변수로 매핑 (checks/*.ps1 이 Invoke-MssqlQuery 를 통해 사용) --------
if ($SqlHost) { $env:DB_HOST = $SqlHost }
if ($SqlPort) { $env:DB_PORT = $SqlPort }
if ($SqlUser) { $env:DB_USER = $SqlUser }
if ($SqlDb)   { $env:DB_NAME = $SqlDb }
if ($env:DB_PASSWORD) { $env:SQLCMDPASSWORD = $env:DB_PASSWORD }
# $env:TEMP 는 Windows 전용이라 Linux(pwsh 7, MSSQL Linux 호스트)에서는 비어 있다 -
# [System.IO.Path]::GetTempPath() 는 두 플랫폼 모두에서 동작한다.
$Global:DbErrFile = Join-Path ([System.IO.Path]::GetTempPath()) "kisa-dbms-err-$PID.txt"

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

if (-not $OutBase) { $OutBase = Join-Path (Split-Path -Parent $ScriptDir) "output" }
$OutDir = New-OutputDir -BaseDir $OutBase -CategoryNum $CategoryNum

Show-Banner -Category $CategoryName -Total $Selected.Count -OsFamily $DbmsEngine
Write-Log "진단 시작: 엔진=$DbmsEngine 대상=$($Selected.Count)항목"

$Results = @()
$CsvRows = @()
$n = 0
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

Remove-Item -Path $Global:DbErrFile -Force -ErrorAction SilentlyContinue

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
