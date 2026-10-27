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

# 실제로 바꾸는 경우(적용/원복)에만: 권한 확인 + 동시 실행 잠금(lib/Common.psm1, 운영 안전 기준 F1/F6).
# 잠금은 아래 try/finally 로 정상 종료·오류·Ctrl+C 모두에서 해제한다.
$FixLock = $null
if ($Apply -or $Rollback) {
    # 관리자 권한 확인은 하지 않는다 - MSSQL 조치는 대부분 SQL 이고 Linux(pwsh) 호스트에서도 실행된다.
    $FixLock = Enter-FixLock -CategoryNum $CategoryNum
    if (-not $FixLock) {
        Write-Error "다른 조치(fix) 실행이 진행 중입니다. 끝난 뒤 다시 실행하세요(변경 없음)."
        exit 2
    }
}

try {

    if ($SqlHost) { $env:DB_HOST = $SqlHost }
    if ($SqlPort) { $env:DB_PORT = $SqlPort }
    if ($SqlUser) { $env:DB_USER = $SqlUser }
    if ($SqlDb)   { $env:DB_NAME = $SqlDb }
    if ($env:DB_USER -and -not $env:DB_PASSWORD) {
        Write-Error "SQL 인증(-SqlUser/DB_USER) 사용 시 `$env:DB_PASSWORD 가 필요합니다(비밀번호 프롬프트 대기 방지)."
        exit 2
    }
    if ($env:DB_PASSWORD) { $env:SQLCMDPASSWORD = $env:DB_PASSWORD }
    $Global:DbErrFile = Join-Path ([System.IO.Path]::GetTempPath()) "kisa-dbms-fix-err-$PID.txt"
    $Global:DbConnFailed = $false

    # 적용/원복은 항목마다 DB에 접속하므로, 잘못된 접속 정보로 로그인 실패를 반복해 계정이 잠기기
    # 전에 1회만 시험하고 실패하면 아무것도 바꾸지 않고 중단한다.
    if ($Apply -or $Rollback) {
        if (-not (Test-MssqlPreflight)) {
            Remove-Item -Path $Global:DbErrFile -Force -ErrorAction SilentlyContinue
            Write-Error "DB 접속 사전 점검 실패 - 계정 잠금 방지를 위해 재시도하지 않고 중단합니다(변경 없음): $Global:DbConnFailMsg"
            exit 2
        }
    }

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

    # -Apply 시 실제로 바뀔 항목(auto 는 항목별 확인 없이 적용)을 먼저 보여주고 1회 확인(-Yes 로 생략)
    if ($Apply -and -not (Confirm-FixPlan -Codes $VulnCodes -GuideByCode $GuideByCode -Yes:$Yes -FixDir (Join-Path $ScriptDir "fixes\mssql"))) {
        Write-Host "중단 — 아무것도 변경하지 않았습니다. (비대화형 실행은 -Yes 로 이 확인을 생략할 수 있음)"
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
    $abortRun = $false

    foreach ($code in $VulnCodes) {
        $meta = $GuideByCode[$code]
        $title = if ($meta) { $meta.title } else { $code }
        $grade = if ($meta -and $meta.fix) { $meta.fix } else { "manual" }

        if ($grade -eq "manual") {
            Write-Host "[$code] $title"
            Write-Host "  등급: manual (자동 조치 없음) — 가이드 조치 방법: $($meta.remediation)"
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$code`tmanual`tMANUAL`t자동 조치 없음(가이드 조치 방법 안내만)" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
            $nManual++
            continue
        }

        $fixFile = Join-Path $ScriptDir "fixes\mssql\$code.ps1"
        $checkFile = Join-Path $ScriptDir "checks\mssql\$code.ps1"

        if (-not (Test-Path $fixFile)) {
            Write-Host "[$code] $title"
            Write-Host "  등급: $grade 이나 조치 스크립트 미구현 — 건너뜀"
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$code`t$grade`tSKIPPED`t조치 스크립트 미구현" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
            $nSkipped++
            continue
        }

        if (-not $Apply) {
            Write-Host "[$code] $title"
            Write-Host "  등급: $grade (dry-run — 실제 적용하려면 -Apply 추가)"
            $rbn = Get-FixRollbackNote -File $fixFile; if ($rbn) { Write-Host "  원복: $rbn" -ForegroundColor Yellow }
            $nPreview++
            continue
        }

        if ($grade -eq "confirm") {
            if (-not (Read-FixConfirm -Prompt "[$code] $title`n  등급: confirm — 실제로 적용하시겠습니까? [y/N]")) {
                Write-Host "  건너뜀 (사용자 미확인)"
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$code`t$grade`tDECLINED`t사용자가 확인하지 않음" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
                $nDeclined++
                continue
            }
        }

        $Global:FixCode = $code
        $Global:FixStatus = "ERROR"; $Global:FixDetail = "조치 스크립트가 결과를 반환하지 않음"; $Global:FixEvidence = ""
        try { & $fixFile } catch {
            $Global:FixStatus = "ERROR"; $Global:FixDetail = "조치 스크립트 실행 중 예외: $($_.Exception.Message)"
            # lib/Common.psm1 백업 함수는 실패 시 "[백업 실패]" 예외를 던진다(변경 전에 멈춤) - 이 항목을 원복한 뒤 실행 중단
            if ($_.Exception.Message.StartsWith("[백업 실패]")) { $abortRun = $true }
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
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$code`t$grade`tAPPLIED`t$($Global:FixDetail) (recheck=$($Global:CheckStatus))" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
            $nApplied++
        } else {
            Write-Host "[$code] $title"
            Write-Host "  적용 실패 또는 재검증 실패(FixStatus=$($Global:FixStatus), 재검증=$($Global:CheckStatus)) — 원복 중"
            # 실제로 되돌리지 못한 부분이 있으면 FAILED_NOT_ROLLED_BACK 으로 정직하게 기록한다(lib/Common.psm1 Add-FixRollbackFailure)
            $Global:FixRollbackFailures = @()
            Restore-FixItem -Code $code
            $rbs = if (@($Global:FixRollbackFailures).Count -eq 0) { "FAILED_ROLLED_BACK" } else { "FAILED_NOT_ROLLED_BACK" }
            if ($rbs -eq "FAILED_NOT_ROLLED_BACK") { Write-Host "  원복하지 못한 부분(수동 확인 필요): $($Global:FixRollbackFailures -join ' / ')" -ForegroundColor Yellow }
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$code`t$grade`t$rbs`tFixStatus=$($Global:FixStatus) detail=$($Global:FixDetail) recheck=$($Global:CheckStatus) $($Global:FixRollbackFailures -join ' / ')" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
            $nFailed++
        }
        Remove-Variable -Name FixCode -Scope Global -ErrorAction SilentlyContinue
        if ($abortRun) {
            Write-Host "백업 실패로 조치 실행을 중단합니다 — 이 항목은 원복했고 이후 항목은 변경하지 않습니다." -ForegroundColor Red
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$code`t$grade`tABORTED`t백업 실패로 실행 중단(이 항목 원복)" | Out-File -FilePath $Global:FixLog -Append -Encoding utf8
            break
        }
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
} finally {
    Exit-FixLock -Mutex $FixLock
}
