# 02_windows/run.ps1 — Windows 서버 진단 진입점 (PowerShell 5.1 호환)
#
# 사용법:
#   .\run.ps1                        전체 항목 일괄 진단, 환경 자동 감지
#   .\run.ps1 -Items W-01,W-05       개별(복수) 항목만 진단
#   .\run.ps1 -Group 1               하위분류 단위(1=계정 관리 등) 진단
#   .\run.ps1 -ListOnly              항목 목록만 출력
#   .\run.ps1 -OutBase <dir>         결과 출력 경로 지정 (기본: ..\output)
#
# 이 스크립트는 대상 시스템 설정을 변경하지 않는다 (진단 전용). 조치는 fix.ps1 참고.

[CmdletBinding()]
param(
    [string]$Items = "",
    [string]$Group = "",
    [switch]$ListOnly,
    [string]$OutBase = ""
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path (Split-Path -Parent $ScriptDir) "lib"
$GuideJsonPath = Join-Path $ScriptDir "guide.json"
$CategoryNum = "02"
$CategoryName = "Windows 서버"

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
$OutDir = New-OutputDir -BaseDir $OutBase -CategoryNum $CategoryNum

Show-Banner -Category $CategoryName -Total $Selected.Count -OsFamily $OsFamily
Write-Log "진단 시작: 환경=$OsFamily 대상=$($Selected.Count)항목"

$Results = @()
$CsvRows = @()
$n = 0
foreach ($code in $Selected) {
    $n++
    $meta = $GuideByCode[$code]
    $title = if ($meta) { $meta.title } else { $code }
    $checkFile = Join-Path $ScriptDir "checks\$code.ps1"

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
