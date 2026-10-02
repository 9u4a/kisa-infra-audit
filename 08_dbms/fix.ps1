# 08_dbms/fix.ps1 — MSSQL 자동 조치 진입점 (PowerShell 5.1 호환)
#
# run.ps1(진단)와 완전히 분리된 진입점이다. Unix 계열 엔진(MySQL/PostgreSQL/Oracle) 대상은
# 별도 08_dbms/fix.sh 를 사용한다. 02_windows/fix.ps1 과 동일한 흐름·CLI를 쓰되, run.ps1 과
# 동일한 접속 매개변수(-SqlHost 등)를 추가로 받는다.
#
# 사용법:
#   .\fix.ps1 -ResultJson <result.json>                        dry-run(미리보기만)
#   .\fix.ps1 -ResultJson <result.json> -SqlUser sa -SqlHost .  SQL 인증으로 접속($env:DB_PASSWORD 필요)
#   .\fix.ps1 -ResultJson <result.json> -Items D-05,D-09 -Apply 지정 항목만 실제 적용
#   .\fix.ps1 -Rollback <output\host_08_fix_TS 디렉터리>         백업에서 원복

[CmdletBinding()]
param(
    [Alias("r")][string]$ResultJson = "",
    [Alias("i")][string]$Items = "",
    [switch]$Apply,
    [switch]$Yes,
    [string]$Rollback = "",
    [Alias("o")][string]$OutBase = "",
    [Alias("h")][switch]$Help,
    [string]$SqlHost = "",
    [string]$SqlPort = "",
    [string]$SqlUser = "",
    [string]$SqlDb = ""
)

if ($Help) {
    Write-Host "사용법:"
    Write-Host "  .\fix.ps1 -ResultJson <result.json>                        dry-run(미리보기만)"
    Write-Host "  .\fix.ps1 -ResultJson <result.json> -SqlUser sa -SqlHost .  SQL 인증(`$env:DB_PASSWORD 필요)"
    Write-Host "  .\fix.ps1 -ResultJson <result.json> -Items D-05,D-09 -Apply 지정 항목만 실제 적용"
    Write-Host "  .\fix.ps1 -Rollback <output\host_08_fix_TS 디렉터리>        백업에서 원복"
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path (Split-Path -Parent $ScriptDir) "lib"
$GuideJsonPath = Join-Path $ScriptDir "guide.json"
$CategoryNum = "08"
$CategoryName = "DBMS (MSSQL)"

Import-Module (Join-Path $LibDir "Common.psm1") -Force

if ($SqlHost) { $env:DB_HOST = $SqlHost }
if ($SqlPort) { $env:DB_PORT = $SqlPort }
if ($SqlUser) { $env:DB_USER = $SqlUser }
if ($SqlDb)   { $env:DB_NAME = $SqlDb }
if ($env:DB_PASSWORD) { $env:SQLCMDPASSWORD = $env:DB_PASSWORD }
$Global:DbErrFile = Join-Path ([System.IO.Path]::GetTempPath()) "kisa-dbms-fix-err-$PID.txt"

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

    $fixFile = Join-Path $ScriptDir "fixes\mssql\$code.ps1"
    $checkFile = Join-Path $ScriptDir "checks\mssql\$code.ps1"

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

Remove-Item -Path $Global:DbErrFile -Force -ErrorAction SilentlyContinue

Write-Host "----------------------------------------------------------------------"
if ($Apply) {
    Write-Host "적용 완료: $nApplied, 실패(원복됨): $nFailed, 확인거부: $nDeclined, 스크립트없음: $nSkipped, 수동조치: $nManual"
    Write-Host "백업 위치: $Global:FixBackupDir"
    Write-Host "원복하려면: .\fix.ps1 -Rollback $Global:FixOutDir"
} else {
    Write-Host "DRY-RUN 미리보기: $nPreview 건 (-Apply 로 실제 적용), 스크립트없음: $nSkipped, 수동조치: $nManual"
}
Write-Host "로그: $Global:FixLog"
