# lib/tests/win_case_runner.ps1 - 항목별 판정 양방향 케이스 실행기(03_web IIS / 08_dbms MSSQL 러너가 dot-source 해서 쓴다)
# GitHub Actions windows-latest(휘발성 VM)에서만 실행한다 - 케이스 준비 스크립트가 IIS 설정·ACL·SQL 상태를 실제로 바꾼다.
# 로컬 개발자 PC에서는 실행 금지.
#
# 케이스 선언: <카테고리>/tests/fixtures/cases/cases.json 의 {"code","engine","name","expect"} (lib/tests/coverage.py 가 센다)
# 케이스 구현: 러너가 넘기는 해시테이블 이름 → @{ Probe; Setup; Cleanup; Want; Fix; FixExpect; NoRollback; Note }
#   Probe   : 상태 지문 한 줄을 출력하는 스크립트(판정과 독립적으로 실제 값을 읽는다 - 준비가 조용히 실패하면 여기서 드러남)
#   Setup   : 상태를 만든다(실패 시 throw)        Cleanup : 되돌린다(실패 시 throw)
#   Want    : 준비 직후 Probe 출력이 맞아야 할 정규식(준비가 실제로 반영됐는지 - 안 맞으면 FAIL, 판정은 보지 않음)
#   Fix     : $true 면 조치 검증(expect=VULN 일 때만) - fixes 스크립트를 fix.ps1 과 같은 방식으로 직접 실행 → 재진단이
#             FixExpect(기본 GOOD, 부분 자동 판정 항목은 MANUAL 허용) → fix.ps1 -Rollback → 재진단 VULN + Probe 가 준비 직후와 같음
#   NoRollback : 조치가 원복 불가로 설계된 항목(Register-FixNoRollback) - 원복 후 상태 비교를 참고로만 표시
#   Params  : 1.7.0 값 지정 조치(fix=param) - @{ <키> = @('값', ...) }. 정책 값($Global:FixParamPolicy)으로 조치하며 expect 가 MANUAL 이어도 검증.
#             Verify(조치 직후 Probe 출력이 맞아야 할 정규식 - 지정 대상만 바뀌었는지), RejectParams(값 검증 실패 → 조치 ERROR + Probe 그대로)
# 흐름: 진단(전) → Probe P0 → Setup → Probe P1(Want) → 진단 = expect → [조치 검증] → Cleanup → Probe = P0 → 진단 = 전
# 선언된 케이스에 구현이 없거나, 예외로 끝나거나, 실행 건수가 선언 건수와 다르면 FAIL.

function Invoke-CaseChild {
    <# 스크립트 텍스트를 새 Windows PowerShell 프로세스에서 실행(모듈·IIS 설정 캐시를 분리). 종료 코드 0 이면 Ok #>
    param([string]$Prelude, [string]$Script)
    $ErrorActionPreference = "Continue"
    $full = "`$ErrorActionPreference = 'Stop'`n$Prelude`ntry {`n$Script`n} catch { Write-Output (""CHILD ERROR: "" + `$_.Exception.Message); exit 1 }`nexit 0"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    $out = & powershell -NoProfile -NonInteractive -EncodedCommand $enc 2>&1 | ForEach-Object { "$_" } | Out-String
    return @{ Ok = ($LASTEXITCODE -eq 0); Out = $out.Trim() }
}

function Invoke-CaseDiag {
    <# run.ps1 -Items <code> 를 새 프로세스로 실행해 그 항목의 판정을 돌려준다 #>
    param([string]$RunPs1, [string[]]$ExtraArgs, [string]$Code, [string]$Tag)
    $out = Join-Path $env:TEMP "case_diag_$Tag"
    Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    $a = @("-NoProfile", "-NonInteractive", "-File", $RunPs1, "-Items", $Code, "-OutBase", $out) + $ExtraArgs
    & powershell @a *>$null
    $path = Get-ChildItem -Path $out -Recurse -Filter result.json -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { return @{ Status = "NO_RESULT"; Detail = "result.json 없음"; Path = $null } }
    $it = (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json).items | Where-Object { $_.code -eq $Code } | Select-Object -First 1
    if (-not $it) { return @{ Status = "NO_RESULT"; Detail = "항목 없음"; Path = $path } }
    return @{ Status = $it.status; Detail = $it.detail; Path = $path }
}

function Get-DeclaredCases {
    param([string]$CasesJson, [string]$Engine)
    if (-not (Test-Path $CasesJson)) { return @() }
    return @((Get-Content -Raw -Encoding UTF8 $CasesJson | ConvertFrom-Json) | Where-Object { $_.engine -eq $Engine })
}

function Invoke-CaseSuite {
    <# 반환: 실패 메시지 배열(비어 있으면 PASS) #>
    param(
        [Parameter(Mandatory)][object[]]$Declared,
        [Parameter(Mandatory)][hashtable]$Impl,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Category,      # 03_web / 08_dbms
        [Parameter(Mandatory)][string]$FixSubDir,     # fixes\iis / fixes\mssql
        [string]$Prelude = "",                        # Probe/Setup/Cleanup 앞에 붙는 공통 함수
        [string]$FixPrelude = "",                     # 직접 조치 실행 전 준비(DB 접속 환경 등)
        [string[]]$DiagArgs = @(),                    # run.ps1 추가 인자(-SqlHost 등)
        [string[]]$RollbackArgs = @(),                # fix.ps1 -Rollback 추가 인자
        [string]$Engine = ""
    )
    $fail = @()
    $runPs1 = Join-Path $Repo "$Category\run.ps1"
    $fixPs1 = Join-Path $Repo "$Category\fix.ps1"
    $guide = @{}
    foreach ($it in (Get-Content -Raw -Encoding UTF8 (Join-Path $Repo "$Category\guide.json") | ConvertFrom-Json).items) { $guide[$it.code] = $it }
    $executed = 0
    $n = 0
    foreach ($c in $Declared) {
        $n++
        $label = "$Engine/$($c.code)/$($c.name)"
        $tag = "$Engine$n"
        if (-not $Impl.ContainsKey($c.name)) { $fail += "${label}: cases.json 에 선언됐지만 구현(Probe/Setup/Cleanup)이 없음 - 실행되지 않은 케이스"; continue }
        $k = $Impl[$c.name]
        Write-Host "[case] $label (기대 $($c.expect))"
        $pre = Invoke-CaseDiag -RunPs1 $runPs1 -ExtraArgs $DiagArgs -Code $c.code -Tag "${tag}_pre"
        $p0 = Invoke-CaseChild -Prelude $Prelude -Script $k.Probe
        if (-not $p0.Ok) { $fail += "${label}: 준비 전 상태 조회 실패 - $($p0.Out)"; continue }
        $cleanupNeeded = $true
        try {
            $s = Invoke-CaseChild -Prelude $Prelude -Script $k.Setup
            if (-not $s.Ok) { $fail += "${label}: 준비 실패 - $($s.Out)"; continue }
            $p1 = Invoke-CaseChild -Prelude $Prelude -Script $k.Probe
            if ([string]::IsNullOrEmpty($k.Want)) { $fail += "${label}: 케이스 구현에 Want(준비 후 기대 상태)가 없음"; continue }
            if (-not $p1.Ok -or $p1.Out -notmatch $k.Want) { $fail += "${label}: 준비 후 상태가 의도와 다름(준비가 반영되지 않음) - 기대 /$($k.Want)/ 실제 '$($p1.Out)'"; continue }
            $mid = Invoke-CaseDiag -RunPs1 $runPs1 -ExtraArgs $DiagArgs -Code $c.code -Tag "${tag}_mid"
            Write-Host "  상태: $($p0.Out) → $($p1.Out) / 판정: $($pre.Status) → $($mid.Status) ($($mid.Detail))"
            if ($mid.Status -ne $c.expect) { $fail += "${label}: 판정 $($mid.Status) - 기대 $($c.expect) ($($mid.Detail))" }
            else { $executed++ }

            $fixFile = Join-Path $Repo "$Category\$FixSubDir\$($c.code).ps1"
            # 1.7.0: 정책 값 정의 줄(Params) - 값 지정 조치는 진단이 MANUAL 이어도 검증한다
            $paramScript = ""
            if ($k.Params) {
                $qv = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
                $pl = @("`$pp = New-Object 'System.Collections.Generic.Dictionary[string,string[]]'")
                foreach ($pk in $k.Params.Keys) { $pl += "`$pp[$(& $qv $pk)] = [string[]]@($((@($k.Params[$pk]) | ForEach-Object { & $qv $_ }) -join ', '))" }
                $pl += "`$pd = New-Object 'System.Collections.Generic.Dictionary[string,object]'; `$pd['$($c.code)'] = `$pp"
                $pl += "`$Global:FixParamPolicy = [PSCustomObject]@{ Params = `$pd; Approver = 'case-runner' }"
                $paramScript = $pl -join "`n"
            }
            if ($k.RejectParams -and $mid.Status -eq $c.expect) {
                # 값 검증 실패: 조치가 ERROR 를 내고 아무것도 바꾸지 않아야 한다(Probe 그대로)
                $qv = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
                $rl = @("`$pp = New-Object 'System.Collections.Generic.Dictionary[string,string[]]'")
                foreach ($pk in $k.RejectParams.Keys) { $rl += "`$pp[$(& $qv $pk)] = [string[]]@($((@($k.RejectParams[$pk]) | ForEach-Object { & $qv $_ }) -join ', '))" }
                $rl += "`$pd = New-Object 'System.Collections.Generic.Dictionary[string,object]'; `$pd['$($c.code)'] = `$pp"
                $rl += "`$Global:FixParamPolicy = [PSCustomObject]@{ Params = `$pd; Approver = 'case-runner' }"
                $rOut = Join-Path $env:TEMP "case_rej_$tag"
                Remove-Item -Recurse -Force $rOut -ErrorAction SilentlyContinue
                $rej = "`$ErrorActionPreference = 'Continue'`nImport-Module '$((Join-Path $Repo 'lib\Common.psm1') -replace "'", "''")' -Force`n$FixPrelude`n" +
                    "New-FixOutputDir -BaseDir '$($rOut -replace "'", "''")' -CategoryNum '$($Category.Substring(0, 2))' | Out-Null`n`$Global:FixCode = '$($c.code)'`n" + ($rl -join "`n") +
                    "`n`$Global:FixStatus = 'ERROR'; `$Global:FixDetail = ''`ntry { & '$($fixFile -replace "'", "''")' } catch { `$Global:FixStatus = 'EXCEPTION'; `$Global:FixDetail = `$_.Exception.Message }`n" +
                    "Write-Output ('DIRECTFIX|' + `$Global:FixStatus + '|' + (`$Global:FixDetail -replace '[\r\n]+', ' '))"
                $rr = Invoke-CaseChild -Prelude "" -Script $rej
                $rm = [regex]::Match($rr.Out, 'DIRECTFIX\|([^|]*)\|(.*)')
                $rs = if ($rm.Success) { $rm.Groups[1].Value } else { "?" }
                $pr = Invoke-CaseChild -Prelude $Prelude -Script $k.Probe
                Write-Host "  값 거부: $rs $(if ($rm.Success) { $rm.Groups[2].Value })"
                if ($rs -ne "ERROR") { $fail += "${label}: 값 검증 실패인데 조치 결과 $rs (ERROR 아님)`n$($rr.Out)" }
                if ($pr.Out -ne $p1.Out) { $fail += "${label}: 값 검증 실패인데 상태가 바뀜 - 전 '$($p1.Out)' / 후 '$($pr.Out)'" }
            }
            if ($k.Fix -and ($c.expect -eq "VULN" -or ($k.Params -and $c.expect -eq "MANUAL")) -and $mid.Status -eq $c.expect) {
                if (-not (Test-Path $fixFile)) { $fail += "${label}: Fix=`$true 인데 조치 스크립트 없음($fixFile)"; continue }
                $fixExpect = if ($k.FixExpect) { @($k.FixExpect) } else { @("GOOD") }
                $dOut = Join-Path $env:TEMP "case_fix_$tag"
                Remove-Item -Recurse -Force $dOut -ErrorAction SilentlyContinue
                $sq = { param($v) $v -replace "'", "''" }
                $direct = @'
$ErrorActionPreference = 'Continue'
Import-Module '__LIB__' -Force
__FIXPRELUDE__
New-FixOutputDir -BaseDir '__OUT__' -CategoryNum '__NUM__' | Out-Null
$Global:FixCode = '__CODE__'
__PARAMS__
$Global:FixStatus = 'ERROR'; $Global:FixDetail = 'no result from fix script'; $Global:FixEvidence = ''
try { & '__FIX__' } catch { $Global:FixStatus = 'ERROR'; $Global:FixDetail = 'exception: ' + $_.Exception.Message }
Write-Output ('DIRECTFIX|' + $Global:FixStatus + '|' + $Global:FixDetail)
'@
                $direct = $direct.Replace("__LIB__", (& $sq (Join-Path $Repo "lib\Common.psm1"))).Replace("__FIXPRELUDE__", $FixPrelude).Replace("__OUT__", (& $sq $dOut)).Replace("__NUM__", $Category.Substring(0, 2)).Replace("__CODE__", $c.code).Replace("__FIX__", (& $sq $fixFile)).Replace("__PARAMS__", $paramScript)
                $d = Invoke-CaseChild -Prelude "" -Script $direct
                $m = [regex]::Match($d.Out, 'DIRECTFIX\|([^|]*)\|(.*)')
                $dStatus = if ($m.Success) { $m.Groups[1].Value } else { "?" }
                $post = Invoke-CaseDiag -RunPs1 $runPs1 -ExtraArgs $DiagArgs -Code $c.code -Tag "${tag}_fix"
                Write-Host "  조치: $dStatus $(if ($m.Success) { $m.Groups[2].Value }) → 재진단 $($post.Status)"
                if ($dStatus -ne "APPLIED") { $fail += "${label}: 조치 결과 $dStatus (APPLIED 아님)`n$($d.Out)" }
                if ($fixExpect -notcontains $post.Status) { $fail += "${label}: 조치 후 판정 $($post.Status) - 기대 $($fixExpect -join '/') ($($post.Detail))" }
                if ($k.Verify) {
                    $pv = Invoke-CaseChild -Prelude $Prelude -Script $k.Probe
                    if ($pv.Out -notmatch $k.Verify) { $fail += "${label}: 조치 후 상태 확인 실패 - 기대 /$($k.Verify)/ 실제 '$($pv.Out)'" }
                }
                $dRun = Get-ChildItem -Path $dOut -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
                if (-not $dRun) { $fail += "${label}: 조치 출력 폴더 없음"; continue }
                $rbArgs = @("-NoProfile", "-NonInteractive", "-File", $fixPs1, "-Rollback", $dRun) + $RollbackArgs
                $rbLog = "" | & powershell @rbArgs 2>&1 | Out-String
                $p3 = Invoke-CaseChild -Prelude $Prelude -Script $k.Probe
                $back = Invoke-CaseDiag -RunPs1 $runPs1 -ExtraArgs $DiagArgs -Code $c.code -Tag "${tag}_rb"
                if ($k.NoRollback) {
                    if ($rbLog -notmatch '원복 일부 실패/불가') { $fail += "${label}: 원복 불가로 설계된 조치인데 원복 로그에 원복 불가 보고가 없음(F4)`n$rbLog" }
                    Write-Host "  원복: 원복 불가 항목(설계) - 원복 후 판정 $($back.Status), 상태 '$($p3.Out)'(참고)"
                } else {
                    if ($rbLog -match '원복 일부 실패/불가') { $fail += "${label}: 원복 일부 실패/불가`n$rbLog" }
                    if ($back.Status -ne $c.expect) { $fail += "${label}: 원복 후 판정 $($back.Status) - 조치 전($($c.expect))과 다름 ($($back.Detail))" }
                    if ($p3.Out -ne $p1.Out) { $fail += "${label}: 원복 후 실제 상태가 조치 전과 다름 - 전 '$($p1.Out)' / 후 '$($p3.Out)'" }
                    else { Write-Host "  원복: 판정 $($back.Status), 상태 동일" }
                }
            } elseif ($c.expect -eq "VULN" -and (Test-Path $fixFile) -and $guide[$c.code].fix -ne "manual" -and -not $k.Fix) {
                if ([string]::IsNullOrWhiteSpace($k.Note)) { $fail += "${label}: 조치 스크립트가 있는데 Fix 검증도, 제외 사유(Note)도 없음" }
                else { Write-Host "  참고: 조치 스크립트가 있으나 이 케이스는 조치 검증 대상 아님 - $($k.Note)" }
            }
        } finally {
            if ($cleanupNeeded) {
                $cl = Invoke-CaseChild -Prelude $Prelude -Script $k.Cleanup
                if (-not $cl.Ok) { $fail += "${label}: 정리 실패 - $($cl.Out)" }
                $p4 = Invoke-CaseChild -Prelude $Prelude -Script $k.Probe
                if ($p4.Out -ne $p0.Out) { $fail += "${label}: 정리 후 상태가 준비 전과 다름 - 전 '$($p0.Out)' / 후 '$($p4.Out)'" }
                $end = Invoke-CaseDiag -RunPs1 $runPs1 -ExtraArgs $DiagArgs -Code $c.code -Tag "${tag}_end"
                if ($end.Status -ne $pre.Status) { $fail += "${label}: 정리 후 판정 $($end.Status) - 준비 전($($pre.Status))과 다름" }
            }
        }
    }
    if ($executed -ne @($Declared).Count) { $fail += "$Engine 케이스: 선언 $(@($Declared).Count)건 중 기대 판정까지 확인된 것 $executed 건 - 실행되지 않았거나 실패한 케이스가 있음" }
    Write-Host "[case] $Engine 케이스 $executed/$(@($Declared).Count) 확인"
    return $fail
}
