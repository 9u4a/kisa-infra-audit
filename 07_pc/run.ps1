# 07_pc/run.ps1 — PC(Windows 10/11) 진단 진입점 (PowerShell 5.1 호환)
#
# 옵션 문자는 전 카테고리와 통일한다 (루트 CLAUDE.md "CLI 옵션 문자 통일" 참고): -l -i -g -o -h
#
# 사용법:
#   .\run.ps1                  전체 항목 일괄 진단
#   .\run.ps1 -i PC-01,PC-05   개별(복수) 항목만 진단
#   .\run.ps1 -g 1             하위분류 단위(1=계정 관리 등) 진단
#   .\run.ps1 -l               항목 목록만 출력
#   .\run.ps1 -o <dir>         결과 출력 경로 지정 (기본: ..\output)
#
# 이 스크립트는 대상 시스템 설정을 변경하지 않는다 (진단 전용). 조치는 fix.ps1 참고.

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
    Write-Host "  .\run.ps1                  전체 항목 일괄 진단"
    Write-Host "  .\run.ps1 -i PC-01,PC-05   개별(복수) 항목만 진단"
    Write-Host "  .\run.ps1 -g 1             하위분류 단위(1=계정 관리 등) 진단"
    Write-Host "  .\run.ps1 -l               항목 목록만 출력"
    Write-Host "  .\run.ps1 -o <dir>         결과 출력 경로 지정 (기본: ..\output)"
    exit 0
}

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path (Split-Path -Parent $ScriptDir) "lib"
$GuideJsonPath = Join-Path $ScriptDir "guide.json"
$CategoryNum = "07"
$CategoryName = "PC"

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

$OsFamily = Get-OsFamily

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
# 비관리자 실행 여부(아래 공통 변환 규칙). 비관리자는 서비스·보안 정책·레지스트리 조회가 조용히 실패해
# "없음/중지/미설정"으로 읽히기 쉽다(CI 실측: W-18 VULN→NA, W-33 VULN→GOOD).
$IsElevatedAdmin = Test-IsElevatedAdmin

Show-Banner -Category $CategoryName -Total $Selected.Count -OsFamily $OsFamily
Write-Log "진단 시작: 환경=$OsFamily 대상=$($Selected.Count)항목"

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
    $checkFile = Join-Path $ScriptDir "checks\$code.ps1"

    if (Test-Path $checkFile) {
        $Global:SecPolicyQueried = $false
        $Global:RegistryQueryFailed = $false; $Global:RegistryQueryError = ""
        try {
            $r = & $checkFile
            if (-not $r) {
                $r = New-CheckResult -Code $code -Status "ERROR" -Detail "check 스크립트가 결과를 반환하지 않음"
            }
        } catch {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "check 실행 중 예외 발생: $($_.Exception.Message)"
        }
        # secedit 내보내기가 실패하면 정책 값이 전부 $null 로 보여 "미설정"으로 오판된다 - 확인하지 못한 판정은 ERROR
        if ($Global:SecPolicyQueried -and $Global:SecEditFailed -and $r.status -in @("GOOD", "VULN")) {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "보안 정책(secedit) 조회에 실패해 판정할 수 없음 - 관리자 권한으로 다시 실행 필요"
        }
        # W-R14: 레지스트리 조회가 권한 거부 등으로 실패했으면(값 없음과 구분) 그 값으로 내린 판정은 ERROR
        if ($Global:RegistryQueryFailed -and $r.status -in @("GOOD", "VULN")) {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "레지스트리 조회에 실패해 판정할 수 없음: $($Global:RegistryQueryError) / 원래 판정: $($r.status) $($r.detail)" -Evidence $r.evidence
        }
        # 비관리자 실행의 GOOD/NA 는 확인하지 못한 결과일 수 있다 - ERROR 로 바꾸고 원래 판정은 detail 에 남긴다
        # (운영 안전 기준 S6, sh 의 nonroot_unverified 와 같은 원칙). VULN/MANUAL 은 그대로 둔다.
        if (-not $IsElevatedAdmin -and $r.status -in @("GOOD", "NA")) {
            $r = New-CheckResult -Code $code -Status "ERROR" -Detail "관리자 권한이 아니어서 확인하지 못함 - 관리자 권한으로 다시 실행 필요 / 비관리자 판정: $($r.status) $($r.detail)" -Evidence $r.evidence
        }
    } else {
        $r = New-CheckResult -Code $code -Status "ERROR" -Detail "check 스크립트 없음 (미구현 항목)"
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
        Save-ResultJson -Results $Results -OutFile (Join-Path $OutDir "result.partial.json") -Category $CategoryName -OsFamily $OsFamily
        Write-Warning "중단됨 - 지금까지 진단한 $(@($Results).Count)개 항목을 $(Join-Path $OutDir 'result.partial.json') 에 저장했습니다."
    }
}
$ResultJson = Join-Path $OutDir "result.json"
Save-ResultJson -Results $Results -OutFile $ResultJson -Category $CategoryName -OsFamily $OsFamily
$CsvRows | Export-Csv -Path (Join-Path $OutDir "result.csv") -NoTypeInformation -Encoding UTF8

New-ReportHtml -LibDir $LibDir -GuideJson $GuideJsonPath -ResultJson $ResultJson -OutHtml (Join-Path $OutDir "report.html")

$counts = @{ VULN = 0; MANUAL = 0; ERROR = 0; NA = 0; GOOD = 0 }
foreach ($r in $Results) { $counts[$r.status]++ }
$base = $counts.VULN + $counts.GOOD
$rate = if ($base -gt 0) { [int](($counts.GOOD * 100) / $base) } else { 0 }

$summary = @"
=== $CategoryName 진단 요약 ===
호스트   : $env:COMPUTERNAME
환경     : $OsFamily
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
