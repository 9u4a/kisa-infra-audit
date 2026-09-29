# 07_pc/fix.ps1 — PC 자동 조치 진입점 (PowerShell 5.1 호환)
#
# run.ps1(진단)와 완전히 분리된 진입점이다. 02_windows/fix.ps1 과 동일한 흐름·CLI를 쓴다
# (`lib/Common.psm1`의 공통 fix 헬퍼 재사용 — 01_unix/fix.sh 의 dry-run→적용→재검증→원복 원칙).
#
# 사용법:
#   .\fix.ps1 -ResultJson <result.json>                        dry-run: 적용 대상·등급만 출력
#   .\fix.ps1 -ResultJson <result.json> -Items PC-01,PC-15 -Apply  지정 항목만 실제 적용
#   .\fix.ps1 -ResultJson <result.json> -Apply -Yes            auto 등급 전체 적용(confirm 은 항상 개별 확인)
#   .\fix.ps1 -Rollback <output\host_07_fix_TS 디렉터리>        백업에서 원복
#
# **실제 검증 범위(0.8.2, 사용자 확인)**: 문법 파싱·BOM·정적분석까지만 확인했고, 실제 Windows 11
# 호스트에서 --Apply 로 레지스트리/서비스/보안정책을 실제로 바꾸는 시험은 수행하지 않았다
# (02_windows/fix.ps1 과 동일한 이유·범위). 07_pc/CLAUDE.md 참고.

[CmdletBinding()]
param(
    [Alias("r")][string]$ResultJson = "",
    [Alias("i")][string]$Items = "",
    [switch]$Apply,
    [switch]$Yes,
    [string]$Rollback = "",
    [Alias("o")][string]$OutBase = "",
    [Alias("h")][switch]$Help
)

if ($Help) {
    Write-Host "사용법:"
    Write-Host "  .\fix.ps1 -ResultJson <result.json>                        dry-run(미리보기만)"
    Write-Host "  .\fix.ps1 -ResultJson <result.json> -Items PC-01,PC-15 -Apply  지정 항목만 실제 적용"
    Write-Host "  .\fix.ps1 -ResultJson <result.json> -Apply -Yes            auto 등급 일괄 적용"
    Write-Host "  .\fix.ps1 -Rollback <output\host_07_fix_TS 디렉터리>        백업에서 원복"
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path (Split-Path -Parent $ScriptDir) "lib"
$GuideJsonPath = Join-Path $ScriptDir "guide.json"
$CategoryNum = "07"
$CategoryName = "PC"

Import-Module (Join-Path $LibDir "Common.psm1") -Force

if ($Rollback) {
    Invoke-FixRollbackAll -RunDir $Rollback
    exit 0
}

if (-not $ResultJson -or -not (Test-Path $ResultJson)) {
    Write-Error "오류: -ResultJson(-r) <result.json> 이 필요합니다 (run.ps1 진단 결과 파일)."
    exit 2
}
if (-not (Test-Path $GuideJsonPath)) {
    Write-Error "오류: $GuideJsonPath 가 없습니다."
    exit 2
}

$Guide = Get-Content -Raw -Encoding UTF8 -Path $GuideJsonPath | ConvertFrom-Json
$GuideByCode = @{}
foreach ($it in $Guide.items) { $GuideByCode[$it.code] = $it }

$VulnCodes = @(Get-ResultVulnCodes -ResultJson $ResultJson)
if ($Items) {
    $wanted = @($Items -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $VulnCodes = @($VulnCodes | Where-Object { $wanted -contains $_ })
}

if ($VulnCodes.Count -eq 0) {
    Write-Host "적용 대상(취약 판정) 항목이 없습니다."
    exit 0
}

if (-not $OutBase) { $OutBase = Join-Path (Split-Path -Parent $ScriptDir) "output" }
New-FixOutputDir -BaseDir $OutBase -CategoryNum $CategoryNum | Out-Null

Write-Host "=== 자동 조치 (도구 v$($Script:ToolVersion) / 가이드 $($Script:GuideVersion)) ===" -ForegroundColor Cyan
Write-Host "카테고리   : $CategoryName"
Write-Host "모드       : $(if ($Apply) { '실제 적용' } else { 'DRY-RUN (미리보기만, 아무 것도 바꾸지 않음)' })"
Write-Host "대상 항목  : $($VulnCodes.Count)개 (진단 결과 중 VULN$(if ($Items) { ', -Items 필터 적용' }))"
Write-Host "----------------------------------------------------------------------"

$nApplied = 0; $nSkipped = 0; $nDeclined = 0; $nFailed = 0; $nManual = 0; $nPreview = 0

foreach ($code in $VulnCodes) {
    $meta = $GuideByCode[$code]
    $title = if ($meta) { $meta.title } else { $code }
    $grade = if ($meta -and $meta.fix) { $meta.fix } else { "manual" }

    if ($grade -eq "manual") {
        Write-Host "[$code] $title"
        Write-Host "  등급: manual (자동 조치 없음) — 가이드 조치 방법: $($meta.remediation)"
        "$code`tmanual`tMANUAL`t자동 조치 없음(가이드 조치 방법 안내만)" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
        $nManual++
        continue
    }

    $fixFile = Join-Path $ScriptDir "fixes\$code.ps1"
    $checkFile = Join-Path $ScriptDir "checks\$code.ps1"

    if (-not (Test-Path $fixFile)) {
        Write-Host "[$code] $title"
        Write-Host "  등급: $grade 이나 조치 스크립트 미구현 — 건너뜀"
        "$code`t$grade`tSKIPPED`t조치 스크립트 미구현" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
        $nSkipped++
        continue
    }

    if (-not $Apply) {
        Write-Host "[$code] $title"
        Write-Host "  등급: $grade (dry-run — 실제 적용하려면 -Apply 추가)"
        $nPreview++
        continue
    }

    if ($grade -eq "confirm") {
        $ans = Read-Host "[$code] $title`n  등급: confirm — 실제로 적용하시겠습니까? [y/N]"
        if ($ans -notmatch "^[yY]$") {
            Write-Host "  건너뜀 (사용자 미확인)"
            "$code`t$grade`tDECLINED`t사용자가 확인하지 않음" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
            $nDeclined++
            continue
        }
    }

    $Global:FixCode = $code
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "조치 스크립트가 결과를 반환하지 않음"; $Global:FixEvidence = ""
    try { & $fixFile } catch {
        $Global:FixStatus = "ERROR"; $Global:FixDetail = "조치 스크립트 실행 중 예외: $($_.Exception.Message)"
    }

    $Global:CheckStatus = "ERROR"; $checkDetail = "check 스크립트 없음"
    if (Test-Path $checkFile) {
        try {
            $r = & $checkFile
            if ($r) { $Global:CheckStatus = $r.status; $checkDetail = $r.detail }
        } catch {
            $Global:CheckStatus = "ERROR"; $checkDetail = "check 실행 중 예외: $($_.Exception.Message)"
        }
    }

    if (($Global:FixStatus -eq "APPLIED" -or $Global:FixStatus -eq "NA") -and $Global:CheckStatus -ne "VULN" -and $Global:CheckStatus -ne "ERROR") {
        Write-Host "[$code] $title"
        Write-Host "  적용 완료 — 재검증 결과: $($Global:CheckStatus) ($($Global:FixDetail))"
        "$code`t$grade`tAPPLIED`t$($Global:FixDetail) (recheck=$($Global:CheckStatus))" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
        $nApplied++
    } else {
        Write-Host "[$code] $title"
        Write-Host "  적용 실패 또는 재검증 실패(FixStatus=$($Global:FixStatus), 재검증=$($Global:CheckStatus)) — 원복 중"
        Restore-FixItem -Code $code
        "$code`t$grade`tFAILED_ROLLED_BACK`tFixStatus=$($Global:FixStatus) detail=$($Global:FixDetail) recheck=$($Global:CheckStatus)" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
        $nFailed++
    }
    Remove-Variable -Name FixCode -Scope Global -ErrorAction SilentlyContinue
}

Write-Host "----------------------------------------------------------------------"
if ($Apply) {
    Write-Host "적용 완료: $nApplied, 실패(원복됨): $nFailed, 확인거부: $nDeclined, 스크립트없음: $nSkipped, 수동조치: $nManual"
    Write-Host "백업 위치: $Global:FixBackupDir"
    Write-Host "원복하려면: .\fix.ps1 -Rollback $Global:FixOutDir"
} else {
    Write-Host "DRY-RUN 미리보기: $nPreview 건 (-Apply 로 실제 적용), 스크립트없음: $nSkipped, 수동조치: $nManual"
}
Write-Host "로그: $Global:FixLog"
