# 03_web/run.ps1 — IIS 진단 진입점 (PowerShell 5.1 호환)
#
# 옵션 문자는 전 카테고리와 통일한다: -l(목록) -i(항목) -g(분류) -o(출력) -h(도움말).
# IIS는 단일 엔진이라 -e 는 생략한다(루트 CLAUDE.md "CLI 옵션 문자 통일" 참고).
# Unix 계열 엔진(Apache/Nginx/Tomcat)은 03_web/run.sh 를 사용한다.
# 이 스크립트는 대상 시스템 설정을 변경하지 않는다 (진단 전용).
#
# 사용법:
#   .\run.ps1                     설치된 IIS 사이트 전체 진단 (관리자 권한 권장)
#   .\run.ps1 -i WEB-04,WEB-09    개별(복수) 항목만 진단
#   .\run.ps1 -g 3                하위분류 단위 진단 (1=계정관리 ... 4=패치및로그관리)
#   .\run.ps1 -l                  항목 목록만 출력

[CmdletBinding()]
param(
    [Alias("i")][string]$Items = "",
    [Alias("g")][string]$Group = "",
    [Alias("l")][switch]$ListOnly,
    [Alias("o")][string]$OutBase = "",
    [Alias("h")][switch]$Help
)

if ($Help) {
    Write-Host "사용법:"
    Write-Host "  .\run.ps1                     설치된 IIS 사이트 전체 진단 (관리자 권한 권장)"
    Write-Host "  .\run.ps1 -i WEB-04,WEB-09    개별(복수) 항목만 진단"
    Write-Host "  .\run.ps1 -g 3                하위분류 단위 진단"
    Write-Host "  .\run.ps1 -l                  항목 목록만 출력"
    exit 0
}

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path (Split-Path -Parent $ScriptDir) "lib"
$GuideJsonPath = Join-Path $ScriptDir "guide.json"
$CategoryNum = "03"
$CategoryName = "Web"
$WebEngine = "iis"

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

if (-not $OutBase) { $OutBase = Join-Path (Split-Path -Parent $ScriptDir) "output" }
# R-12: 결과 폴더 접근 권한을 제한하지 못하면 New-PrivateDirectory 가 중단시킨다(예전에는 경고만 하고 진행)
try { $OutDir = New-OutputDir -BaseDir $OutBase -CategoryNum $CategoryNum }
catch { Write-Error "결과 폴더 준비 실패: $($_.Exception.Message)"; exit 2 }
# 비관리자 실행이면서 IIS 가 설치되어 있으면(레지스트리 Services\W3SVC) GOOD/NA 를 ERROR 로 바꾼다 - CI 실측: 비관리자
# 실행에서 IIS 설정을 읽지 못해 26항목 전부 NA 였다(관리자 실행은 8항목 VULN). IIS 미설치(키 없음)의 NA 는 그대로 둔다.
$IsElevatedAdmin = Test-IsElevatedAdmin
$IisInstalled = Test-IisInstalled

if (-not (Test-IisAvailable)) {
    Write-Log "IIS(WebAdministration 모듈)를 찾을 수 없습니다. 모든 항목이 NA 로 표시됩니다." "WARN"
}

Show-Banner -Category $CategoryName -Total $Selected.Count -OsFamily $WebEngine
Write-Log "진단 시작: 엔진=$WebEngine 대상=$($Selected.Count)항목"

$Results = @()
$CsvRows = @()
$n = 0
$iisUnreadable = Test-IisInstalledButUnreadable
if ($iisUnreadable) { Write-Log "IIS 가 설치되어 있으나 설정을 읽을 수 없습니다(관리자 권한 필요) - IIS 항목을 ERROR 로 표시합니다." "WARN" }
# 중단(Ctrl+C·예외)돼도 그때까지 진단한 항목을 result.partial.json 으로 남긴다(운영 안전 기준 S7) -
# 예전에는 결과를 루프가 끝난 뒤 한 번만 저장해 중단되면 run.log/raw 만 남았다.
$runCompleted = $false
try {
foreach ($code in $Selected) {
    $n++
    $meta = $GuideByCode[$code]
    $title = if ($meta) { $meta.title } else { $code }
    $checkFile = Join-Path $ScriptDir "checks\iis\$code.ps1"

    if ($iisUnreadable -and (Test-Path $checkFile)) {
        # IIS 는 설치돼 있으나 설정을 읽을 수 없음 - 예전처럼 "IIS 미설치(NA)"로 숨기지 않는다
        $r = New-CheckResult -Code $code -Status "ERROR" -Detail "IIS(W3SVC)가 설치되어 있으나 IIS 설정을 읽을 수 없음 - 관리자 권한으로 다시 실행 필요"
    } elseif (Test-Path $checkFile) {
        $Global:IisConfigQueryFailed = $false; $Global:IisConfigQueryError = ""; $Global:IisSiteListFailed = $false
        try {
            $r = & $checkFile
            if (-not $r) {
                $r = New-CheckResult -Code $code -Status "ERROR" -Detail "check 스크립트가 결과를 반환하지 않음"
            }
        } catch {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "check 실행 중 예외 발생: $($_.Exception.Message)"
        }
        # Get-IisConfigValue 는 조회 실패 시에도 $null(=설정 없음)을 돌려주므로, 그 항목의 GOOD 은
        # 확인하지 못한 채 내린 판정일 수 있다 - ERROR 로 바꾼다(VULN/MANUAL 은 그대로 둠).
        if ($Global:IisConfigQueryFailed -and $r.status -eq "GOOD") {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "IIS 설정 조회에 실패해 양호 판정을 확정할 수 없음: $($Global:IisConfigQueryError)" -Evidence $r.evidence
        }
        # WEB-R7: 사이트 목록 조회 실패는 "사이트 없음(NA)"이 아니다
        if ($Global:IisSiteListFailed -and $r.status -eq "NA") {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "IIS 사이트 목록 조회에 실패해 판정할 수 없음: $($Global:IisConfigQueryError)" -Evidence $r.evidence
        }
    } else {
        $r = New-CheckResult -Code $code -Status "NA" -Detail "이 항목은 IIS 대상이 아니거나 아직 구현되지 않음"
    }

    if (-not $IsElevatedAdmin -and $IisInstalled -and $r.status -in @("GOOD", "NA")) {
        $r = New-CheckResult -Code $code -Status "ERROR" -Detail "관리자 권한이 아니어서 확인하지 못함 - 관리자 권한으로 다시 실행 필요 / 비관리자 판정: $($r.status) $($r.detail)" -Evidence $r.evidence
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
        Save-ResultJson -Results $Results -OutFile (Join-Path $OutDir "result.partial.json") -Category $CategoryName -OsFamily $WebEngine
        Write-Warning "중단됨 - 지금까지 진단한 $(@($Results).Count)개 항목을 $(Join-Path $OutDir 'result.partial.json') 에 저장했습니다."
    }
}
$ResultJson = Join-Path $OutDir "result.json"
Save-ResultJson -Results $Results -OutFile $ResultJson -Category $CategoryName -OsFamily $WebEngine
$CsvRows | Export-Csv -Path (Join-Path $OutDir "result.csv") -NoTypeInformation -Encoding UTF8

New-ReportHtml -LibDir $LibDir -GuideJson $GuideJsonPath -ResultJson $ResultJson -OutHtml (Join-Path $OutDir "report.html")

$counts = @{ VULN = 0; MANUAL = 0; ERROR = 0; NA = 0; GOOD = 0 }
foreach ($r in $Results) { $counts[$r.status]++ }
$base = $counts.VULN + $counts.GOOD
$rate = if ($base -gt 0) { [int](($counts.GOOD * 100) / $base) } else { 0 }

$summary = @"
=== $CategoryName 진단 요약 ===
호스트   : $env:COMPUTERNAME
환경     : $WebEngine
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
