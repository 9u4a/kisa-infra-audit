# 02_windows/tests/case_runner.ps1 -Category <02_windows|07_pc> [-Only W-04,W-08]
# 항목별 양방향 판정 케이스 실행기(1.4.0). GitHub Actions windows-latest(휘발성 Windows Server VM)에서만 실행한다 -
# 실제 보안 정책·레지스트리·서비스·공유·ACL·방화벽·감사 정책을 바꾼다. 로컬 개발자 PC 에서는 절대 실행하지 말 것.
#
# 입력: <카테고리>/tests/fixtures/cases/cases.json  [{"code","engine","name","expect"}]  (lib/tests/coverage.py 가 세는 선언)
#       <카테고리>/tests/fixtures/cases/<코드>.ps1     케이스 정의(해시테이블을 반환하는 스크립트):
#   @{
#     States = [ordered]@{                                    # cases.json 의 name 과 같은 키
#       '<상태>' = @{
#         Reg  = @( @{ P = <경로>; N = <이름>; V = <값, $null=제거>; T = <형식, 기본 DWord> } )   # 설정 후 되읽어 확인, 자동 백업/원복
#         Sec  = @{ '<섹션>' = @{ <키> = <값> } }              # secedit(System Access / Privilege Rights), 자동 확인·원복
#         Svc  = @{ <서비스> = 'Running'|'Stopped'|'Disabled' }  # 자동 확인·원복
#         Set  = { ... }   Check = { ... $true 또는 실패 설명 }   # 그 밖의 상태(Set 이 있으면 Check 필수)
#       } }
#     Resources = @( @{ Save = { 저장 객체 }; Restore = { param($s) ... } } , @{ Svc = '<서비스>' } )   # 추가 원복 대상
#     Fix   = @{ From = '<상태>'; Expect = 'GOOD'; AfterRollback = '<판정>'; SoftAreas = @(); SoftLines = @(); Irreversible = '<사유>' }
#             # 조치 검증. AfterRollback/SoftAreas 는 원복 불가(Register-FixNoRollback)로 선언된 조치만, Irreversible 은 되돌릴 대상이 없는 조치(서명 업데이트)
#     Chain = @{ From = '<상태>'; Codes = @('W-04','W-08') }   # 한 프로세스에서 조치 연속 적용(X-02 회귀)
#     FixSkip = '<사유>'                                       # auto/confirm 조치가 있지만 이 케이스로 검증하지 않는 이유
#   }
# 흐름(항목마다): 상태 스냅샷 → 원복 대상 저장 → 상태별 [설정 → 되읽기 확인(실패 = FAIL, 조용히 PASS 금지) → run.ps1 -i <코드> →
#   기대 판정 비교 → (Fix.From 이면) 조치 직접 실행·재진단·fix.ps1 -Rollback·원복 확인 → 원복] → 상태 스냅샷 비교(원복 확인).
# cases.json 의 케이스가 하나라도 실행되지 않으면 FAIL 이다.
param(
    [Parameter(Mandatory = $true)][ValidateSet("02_windows", "07_pc")][string]$Category,
    [string]$Only = ""
)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$runPs1 = Join-Path $Repo "$Category\run.ps1"
$fixPs1 = Join-Path $Repo "$Category\fix.ps1"
$CategoryNum = $Category.Substring(0, 2)
$CasesDir = Join-Path $Repo "$Category\tests\fixtures\cases"
$Work = Join-Path $env:TEMP "rs_cases"
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Work | Out-Null
. (Join-Path $Repo "lib\tests\win_state_snapshot.ps1")
. (Join-Path $PSScriptRoot "case_lib.ps1")

$Engine = if ($Category -eq "02_windows") { "server" } else { "windows" }
$GuideByCode = @{}
foreach ($it in (Get-Content -Raw -Encoding UTF8 (Join-Path $Repo "$Category\guide.json") | ConvertFrom-Json).items) { $GuideByCode[$it.code] = $it }
# 상태 비교에서 늘 참고로만 보는 범위(fix_safety_windows.ps1 과 같은 기준): IIS 설정 파일 해시(같은 값을 다시 써도 바뀜),
# Windows\Temp(Defender·서비스가 수시로 씀)
$AlwaysSoft = @("iis")
$AlwaysSoftLines = @('^W\|')
# 방화벽 "규칙" 줄(rule/port/addr)은 참고로만: 공유 생성·Server 서비스 재시작·IIS 기동 뒤 OS 가 비동기로 파일 서버·앱 규칙을 켜거나
# 만든다(CI run 40981289087 - W-16/PC-04 뒤 GUID 이름 규칙·FileServer-ServerManager-* 가 다음 항목 중에 나타남). 02/07 의 check 는
# 규칙을 판정에 쓰지 않고, 규칙을 바꾸는 조치(W-64/PC-15 Enable-FixFirewallSafely)는 케이스 정의의 FirewallRulesHard 로 실패 대상에 둔다.
# 프로필(profile|) 줄은 항상 실패 대상이다.

$fail = New-Object System.Collections.ArrayList
function Add-Fail([string]$m) { [void]$fail.Add($m); Write-Host "  FAIL: $m" -ForegroundColor Red }

# Windows PowerShell 5.1 의 ConvertFrom-Json 은 배열을 객체 하나로 내보낸다 - 파이프로 펼친다
$cases = @((Get-Content -Raw -Encoding UTF8 (Join-Path $CasesDir "cases.json") | ConvertFrom-Json) | ForEach-Object { $_ })
$valid = @("GOOD", "VULN", "MANUAL", "NA", "ERROR")
foreach ($c in $cases) {
    if (-not $c.code -or -not $c.name -or $valid -notcontains $c.expect) { throw "cases.json 형식 오류: $($c | ConvertTo-Json -Compress)" }
    if ($c.engine -and $c.engine -ne $Engine) { throw "cases.json 엔진 오류(기대 $Engine): $($c | ConvertTo-Json -Compress)" }
    if (-not $GuideByCode.ContainsKey($c.code)) { throw "guide.json 에 없는 코드: $($c.code)" }
}
$codes = @($cases | ForEach-Object { $_.code } | Select-Object -Unique)
if ($Only) { $want = @($Only -split ',' | ForEach-Object { $_.Trim() }); $codes = @($codes | Where-Object { $want -contains $_ }) }
$executed = @{}

function Invoke-Diag([string]$Codes, [string]$Tag) {
    $out = Join-Path $Work "d_$Tag"
    Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    & powershell -NoProfile -NonInteractive -File $runPs1 -Items $Codes -OutBase $out *>$null
    $path = Get-ChildItem -Path $out -Recurse -Filter result.json -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { throw "진단 결과(result.json)를 찾지 못함($Tag)" }
    $m = @{}
    foreach ($it in (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json).items) { $m[$it.code] = $it }
    return @{ Path = $path; Map = $m }
}

function Invoke-Child([string]$Script) {
    $ErrorActionPreference = "Continue"
    $full = "try {`n$Script`n} catch { Write-Output (""CHILD ERROR: "" + `$_.Exception.Message); exit 1 }`nexit 0"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    $out = & powershell -NoProfile -NonInteractive -EncodedCommand $enc 2>&1 | ForEach-Object { "$_" } | Out-String
    return @{ Ok = ($LASTEXITCODE -eq 0); Out = $out.Trim() }
}

function Invoke-Rollback([string]$RunDir) {
    $ErrorActionPreference = "Continue"
    return ("" | & powershell -NoProfile -NonInteractive -File $fixPs1 -Rollback $RunDir 2>&1 | Out-String)
}

function Get-RegSpecs($st) { if ($st.Reg) { return @($st.Reg) } else { return @() } }   # 원소는 @{ P=경로; N=이름; V=값($null=제거); T=형식 }

function Set-State($st) {
    <# 상태 설정 후 되읽어 확인. 반환: 확인 실패 설명 목록(비어 있으면 설정이 실제로 반영됨) #>
    $probs = @()
    foreach ($r in (Get-RegSpecs $st)) { Set-CaseReg -Path $r.P -Name $r.N -Value $r.V -Type $(if ($r.T) { $r.T } else { "DWord" }) }
    if ($st.Sec) { foreach ($sec in $st.Sec.Keys) { Set-CaseSecPolicy -Section $sec -Values $st.Sec[$sec] } }
    if ($st.Svc) { foreach ($n in $st.Svc.Keys) { Set-CaseService -Name $n -State $st.Svc[$n] } }
    if ($st.Set) { & $st.Set }
    foreach ($r in (Get-RegSpecs $st)) {
        $v = Get-CaseReg -Path $r.P -Name $r.N
        if ("$v" -ne "$($r.V)" -or (($null -eq $v) -ne ($null -eq $r.V))) { $probs += "레지스트리 $($r.P)\$($r.N) = '$v' (설정값 '$($r.V)')" }
    }
    if ($st.Sec) {
        $exp = Export-CaseSecPolicy
        foreach ($sec in $st.Sec.Keys) {
            foreach ($k in $st.Sec[$sec].Keys) {
                $want = "$($st.Sec[$sec][$k])"
                $got = if ($exp.ContainsKey($sec) -and $exp[$sec].ContainsKey($k)) { "$($exp[$sec][$k])" } else { $null }
                $same = if ($sec -eq "Privilege Rights") { (ConvertTo-CasePrivSet $got) -eq (ConvertTo-CasePrivSet $want) } else { $got -eq $want }
                if (-not $same) { $probs += "보안 정책 [$sec] $k = '$got' (설정값 '$want')" }
            }
        }
    }
    if ($st.Svc) {
        foreach ($n in $st.Svc.Keys) {
            $s = Get-CaseService -Name $n
            $want = $st.Svc[$n]
            if (-not $s) { if ($want -eq "Running") { $probs += "서비스 $n 없음" }; continue }
            $ok = switch ($want) { "Running" { $s.State -eq "Running" } "Stopped" { $s.State -eq "Stopped" } "Disabled" { $s.State -eq "Stopped" -and $s.StartMode -eq "Disabled" } }
            if (-not $ok) { $probs += "서비스 $n = $($s.State)/$($s.StartMode) (설정값 $want)" }
        }
    }
    if ($st.Set -and -not $st.Check) { $probs += "Set 이 있는 상태에 Check 가 없음(설정 반영을 확인할 수 없음)" }
    if ($st.Check) {
        $r = & $st.Check
        if ($r -ne $true) { $probs += "Check: $r" }
    }
    return $probs
}

function Save-Resources($def) {
    <# 상태들이 건드리는 자원을 미리 저장 - 반환: 원복 스크립트 목록(역순 실행) #>
    $saved = New-Object System.Collections.ArrayList
    $regSeen = @{}; $svcSeen = @{}; $needSec = $false
    $res = @()
    if ($def.Resources) { $res += @($def.Resources) }
    # 사용자 정의 원복(공유 재생성·사이트 삭제 등)은 맨 마지막에 실행되도록 먼저 저장한다(원복은 역순) - 예: W-17 은
    # AutoShareServer 레지스트리가 먼저 원래대로 돌아와야 Server 서비스 재시작으로 기본 공유가 다시 생긴다
    foreach ($r in $res) {
        if ($r.Save) { [void]$saved.Add(@{ Label = "custom"; Do = $r.Restore; Obj = (& $r.Save) }) }
    }
    foreach ($stName in $def.States.Keys) {
        $st = $def.States[$stName]
        foreach ($r in (Get-RegSpecs $st)) {
            $key = "$($r.P)|$($r.N)"
            if ($regSeen.ContainsKey($key)) { continue }
            $regSeen[$key] = $true
            $kExists = Test-Path -LiteralPath $r.P
            $kind = $null; $val = Get-CaseReg -Path $r.P -Name $r.N
            if ($null -ne $val) { $kind = (Get-Item -LiteralPath $r.P).GetValueKind($r.N).ToString() }
            [void]$saved.Add(@{ Label = "reg $key"; Do = {
                        param($o)
                        if ($null -ne $o.Val) { Set-CaseReg -Path $o.Path -Name $o.Name -Value $o.Val -Type $o.Kind }
                        else {
                            Set-CaseReg -Path $o.Path -Name $o.Name -Value $null
                            if (-not $o.KeyExisted -and (Test-Path -LiteralPath $o.Path)) { Remove-Item -LiteralPath $o.Path -Recurse -Force }
                        }
                    }; Obj = @{ Path = $r.P; Name = $r.N; Val = $val; Kind = $kind; KeyExisted = $kExists } })
        }
        if ($st.Sec) { $needSec = $true }
        if ($st.Svc) { foreach ($n in $st.Svc.Keys) { $svcSeen[$n] = $true } }
    }
    foreach ($r in $res) { if ($r.Svc) { $svcSeen[$r.Svc] = $true } }
    foreach ($n in $svcSeen.Keys) {
        $svcObj = Get-CaseService -Name $n
        [void]$saved.Add(@{ Label = "svc $n"; Do = { param($o) Restore-CaseService -Saved $o }; Obj = $svcObj })
        # RemoteRegistry 를 켜는 상태는 DisableIdleStop 도 쓴다
        if ($n -eq "RemoteRegistry") {
            $p = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters"
            $v = Get-CaseReg -Path $p -Name DisableIdleStop
            [void]$saved.Add(@{ Label = "reg RemoteRegistry DisableIdleStop"; Do = { param($o) Set-CaseReg -Path $o.P -Name DisableIdleStop -Value $o.V }; Obj = @{ P = $p; V = $v } })
        }
    }
    if ($needSec) {
        $f = Join-Path $global:CaseTmpRoot ("sec_" + ([guid]::NewGuid().ToString("N")) + ".inf")
        & secedit.exe /export /cfg $f /quiet | Out-Null   # fix 백업(Backup-FixSecPolicy)과 같은 전체 내보내기
        if ($LASTEXITCODE -ne 0) { throw "보안 정책 백업(secedit /export) 실패" }
        [void]$saved.Add(@{ Label = "secpolicy"; Do = { param($o) Invoke-CaseSecedit -Cfg $o -Areas @("SECURITYPOLICY", "USER_RIGHTS") }; Obj = $f })
    }
    return , $saved   # ArrayList 를 그대로(원소 1개일 때 해시테이블로 풀리지 않게)
}

function Restore-Resources($saved) {
    $saved = @($saved)
    for ($i = $saved.Count - 1; $i -ge 0; $i--) {
        $s = $saved[$i]
        try { & $s.Do $s.Obj } catch { Add-Fail "원복 실패($($s.Label)): $($_.Exception.Message)" }
    }
}

function Get-Snap([string]$Label) {
    <# 상태 스냅샷 - 조회 자체가 예외로 끝나면(예: 계정 이름 매핑 실패) 기록하고 $null(비교 생략, 실행은 계속) #>
    # firefox: 러너 이미지의 Firefox 가 실행 계정 TEMP 에 프로필 잠금(firefox\parent.lock)을 수시로 만든다 - CI run 41046713452 W-01 구간
    try { return (Get-WinStateSnapshot -Category $Category -TempExclude @("rs_*", "fs_*", "firefox")) }
    catch { Add-Fail "$Label : 상태 스냅샷 실패 - $($_.Exception.Message)"; return $null }
}

function Compare-Snap($Before, $After, [string[]]$Soft, [string[]]$SoftL, [string]$Label) {
    if (-not $Before -or -not $After) { return }
    $cmp = Compare-WinStateSnapshot -Before $Before -After $After -SoftAreas $Soft -SoftLinePatterns $SoftL -Label $Label
    foreach ($f in $cmp.Fail) { Add-Fail $f }
    $cmp.Notes | ForEach-Object { Write-Host "    · $_" }
}

function Test-Expect($diag, [string]$code, [string]$expect, [string]$label) {
    $it = $diag.Map[$code]
    $st = if ($it) { $it.status } else { "(없음)" }
    if ($st -ne $expect) { Add-Fail "$label : 기대 $expect, 실제 $st - $(if ($it) { $it.detail })"; return $false }
    Write-Host "  OK $label -> $st"
    return $true
}

function Invoke-FixFlow($def, [string]$code, [string]$stName, [string]$stExpect, $st) {
    $fx = $def.Fix
    $fixFile = Join-Path $Repo "$Category\fixes\$code.ps1"
    $label = "$code/$stName 조치"
    $sV = Get-Snap "$label 전"
    $dOut = Join-Path $Work "fix_$code"
    Remove-Item -Recurse -Force $dOut -ErrorAction SilentlyContinue
    $q = { param($s) $s -replace "'", "''" }
    $direct = @'
$ErrorActionPreference = 'Continue'
Import-Module '__LIB__' -Force
New-FixOutputDir -BaseDir '__OUT__' -CategoryNum '__NUM__' | Out-Null
$Global:FixCode = '__CODE__'
$Global:FixStatus = 'ERROR'; $Global:FixDetail = 'no result from fix script'; $Global:FixEvidence = ''
try { & '__FIX__' } catch { $Global:FixStatus = 'ERROR'; $Global:FixDetail = 'exception: ' + $_.Exception.Message }
$line = 'DIRECTFIX|' + $Global:FixStatus + '|' + ($Global:FixDetail -replace '[\r\n]+', ' ')
Set-Content -LiteralPath '__RES__' -Value $line -Encoding UTF8
Write-Output $line
'@
    $resFile = Join-Path $Work "fixres_$code.txt"; Remove-Item -LiteralPath $resFile -Force -ErrorAction SilentlyContinue
    $direct = $direct.Replace("__RES__", (& $q $resFile)).Replace("__LIB__", (& $q (Join-Path $Repo "lib\Common.psm1"))).Replace("__OUT__", (& $q $dOut)).Replace("__NUM__", $CategoryNum).Replace("__CODE__", $code).Replace("__FIX__", (& $q $fixFile))
    $d = Invoke-Child $direct
    $resText = if (Test-Path -LiteralPath $resFile) { Get-Content -Raw -Encoding UTF8 -LiteralPath $resFile } else { $d.Out }
    $m = [regex]::Match($resText, 'DIRECTFIX\|([^|]*)\|(.*)')
    $dStatus = if ($m.Success) { $m.Groups[1].Value } else { "?" }
    Write-Host "  조치: $dStatus $(if ($m.Success) { $m.Groups[2].Value })"
    if ($dStatus -ne "APPLIED") { Add-Fail "$label : 조치 결과가 APPLIED 가 아님($dStatus) - 자식 종료 Ok=$($d.Ok)`n$($d.Out)" }
    $want = if ($fx.Expect) { $fx.Expect } else { "GOOD" }
    [void](Test-Expect (Invoke-Diag $code "${code}_fixed") $code $want "$label 후 재진단")
    $dRun = Get-ChildItem -Path $dOut -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $dRun) { Add-Fail "$label : 조치 출력 폴더 없음"; return }
    $rbLog = Invoke-Rollback $dRun
    $partial = $rbLog -match '원복 일부 실패/불가'
    $declared = [bool]($fx.SoftAreas -or $fx.SoftLines -or $fx.AfterRollback)
    if ($partial -and -not $declared) { Add-Fail "$label : 원복 일부 실패/불가`n$rbLog" }
    if (-not $partial -and $declared -and $fx.AfterRollback -and $fx.AfterRollback -ne $stExpect -and -not $fx.Irreversible) { Add-Fail "$label : 원복 불가로 선언했는데 fix.ps1 -Rollback 이 원복 불가를 보고하지 않음(F4)`n$rbLog" }
    $after = if ($fx.AfterRollback) { $fx.AfterRollback } else { $stExpect }
    [void](Test-Expect (Invoke-Diag $code "${code}_rb") $code $after "$label 원복 후 재진단")
    if (-not $fx.AfterRollback) {
        # 판정뿐 아니라 설정한 값 자체가 조치 전(취약 상태)으로 돌아왔는지
        $p = @()
        foreach ($r in (Get-RegSpecs $st)) { $v = Get-CaseReg -Path $r.P -Name $r.N; if ("$v" -ne "$($r.V)") { $p += "$($r.P)\$($r.N)='$v'" } }
        if ($st.Check) { $c = & $st.Check; if ($c -ne $true) { $p += "Check: $c" } }
        if ($p.Count -gt 0) { Add-Fail "$label : 원복 후 취약 상태로 돌아오지 않음 - $($p -join ' / ')" }
    }
    $sR = Get-Snap "$label 원복 후"
    $soft = @($AlwaysSoft) + @($fx.SoftAreas | Where-Object { $_ })
    $softL = @($AlwaysSoftLines) + @($fx.SoftLines | Where-Object { $_ }) + $(if ($def.FirewallRulesHard) { @() } else { @('^(rule|port|addr)\|') })
    Compare-Snap $sV $sR $soft $softL "$label 원복"
}

function Invoke-ChainFlow($def, [string]$code) {
    <# X-02 회귀: 같은 프로세스에서 보안 정책(secedit) 조치 두 개를 연달아 적용하고 각각 같은 프로세스에서 재검증.
       Set-FixSecPolicyValue 가 진단 캐시(Get-SecEditExport)를 비우지 않으면 두 번째 재검증이 변경 전 값을 읽어 VULN 이 된다.
       fix.ps1 처럼 재검증 전에 직접 캐시를 비우지 않는다 - 공통 모듈의 캐시 무효화만 검증하기 위해 #>
    $ch = $def.Chain
    $label = "$code 연속 조치($($ch.Codes -join ' → '))"
    $sV = Get-Snap "$label 전"
    $pre = Invoke-Diag ($ch.Codes -join ",") "${code}_chain_pre"
    foreach ($c in $ch.Codes) { [void](Test-Expect $pre $c "VULN" "$label 전 $c") }
    $dOut = Join-Path $Work "chain_$code"
    Remove-Item -Recurse -Force $dOut -ErrorAction SilentlyContinue
    $q = { param($s) $s -replace "'", "''" }
    $lines = @("`$ErrorActionPreference = 'Continue'", "Import-Module '$(& $q (Join-Path $Repo 'lib\Common.psm1'))' -Force",
        "New-FixOutputDir -BaseDir '$(& $q $dOut)' -CategoryNum '$CategoryNum' | Out-Null",
        "`$null = Get-SecPolicyValue -Section 'System Access' -Name 'MinimumPasswordLength'   # 캐시를 채워 둔다(앞선 진단·재검증이 있었던 세션과 같게)")
    foreach ($c in $ch.Codes) {
        $lines += "`$Global:FixCode = '$c'; `$Global:FixStatus = 'ERROR'; `$Global:FixDetail = ''"
        $lines += "try { & '$(& $q (Join-Path $Repo "$Category\fixes\$c.ps1"))' } catch { `$Global:FixStatus = 'ERROR'; `$Global:FixDetail = `$_.Exception.Message }"
        $lines += "`$r = & '$(& $q (Join-Path $Repo "$Category\checks\$c.ps1"))'"
        $lines += "Write-Output ('CHAIN|$c|' + `$Global:FixStatus + '|' + `$r.status + '|' + `$r.detail)"
    }
    $d = Invoke-Child ($lines -join "`n")
    foreach ($c in $ch.Codes) {
        $m = [regex]::Match($d.Out, "CHAIN\|$c\|([^|]*)\|([^|]*)\|(.*)")
        if (-not $m.Success) { Add-Fail "$label : $c 결과 없음`n$($d.Out)"; continue }
        Write-Host "  $c 조치 $($m.Groups[1].Value) / 같은 프로세스 재검증 $($m.Groups[2].Value)"
        if ($m.Groups[1].Value -ne "APPLIED" -or $m.Groups[2].Value -ne "GOOD") { Add-Fail "$label : $c 조치 $($m.Groups[1].Value), 재검증 $($m.Groups[2].Value) ($($m.Groups[3].Value)) - 보안 정책 캐시가 조치 후 비워지지 않았을 수 있음(X-02)" }
    }
    $post = Invoke-Diag ($ch.Codes -join ",") "${code}_chain_post"
    foreach ($c in $ch.Codes) { [void](Test-Expect $post $c "GOOD" "$label 후 $c(새 프로세스)") }
    $dRun = Get-ChildItem -Path $dOut -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($dRun) {
        $rbLog = Invoke-Rollback $dRun
        if ($rbLog -match '원복 일부 실패/불가') { Add-Fail "$label : 원복 일부 실패/불가`n$rbLog" }
    } else { Add-Fail "$label : 조치 출력 폴더 없음" }
    $rb = Invoke-Diag ($ch.Codes -join ",") "${code}_chain_rb"
    foreach ($c in $ch.Codes) { [void](Test-Expect $rb $c "VULN" "$label 원복 후 $c") }
    $sR = Get-Snap "$label 원복 후"
    Compare-Snap $sV $sR $AlwaysSoft (@($AlwaysSoftLines) + @('^(rule|port|addr)\|')) "$label 원복"
}

# ---- 실행 -----------------------------------------------------------------------
$t0 = Get-Date
$snap = Get-Snap "시작"
foreach ($code in $codes) {
    $tc = Get-Date
    $file = Join-Path $CasesDir "$code.ps1"
    Write-Host "[$Category] $code"
    if (-not (Test-Path $file)) { Add-Fail "${code}: 케이스 정의 파일 없음($file)"; continue }
    $def = & $file
    $mine = @($cases | Where-Object { $_.code -eq $code })
    foreach ($k in $def.States.Keys) { if (-not ($mine | Where-Object { $_.name -eq $k })) { Add-Fail "${code}: 정의에만 있고 cases.json 에 없는 상태 '$k'" } }
    $grade = "$($GuideByCode[$code].fix)"
    $hasFix = (Test-Path (Join-Path $Repo "$Category\fixes\$code.ps1")) -and $grade -in @("auto", "confirm")
    if ($hasFix -and -not $def.Fix -and -not $def.FixSkip -and ($mine | Where-Object { $_.expect -eq "VULN" })) {
        Add-Fail "${code}: $grade 등급 조치가 있는데 케이스 정의에 Fix(또는 FixSkip 사유)가 없음"
    }
    $saved = $null
    try {
        $saved = Save-Resources $def
        foreach ($c in $mine) {
            $st = $def.States[$c.name]
            if (-not $st) { Add-Fail "${code}: cases.json 의 상태 '$($c.name)' 정의 없음"; continue }
            Write-Host " - $($c.name) (기대 $($c.expect))"
            $probs = @()
            try { $probs = @(Set-State $st) } catch { $probs = @("설정 중 예외: $($_.Exception.Message)") }
            if ($probs.Count -gt 0) {
                Add-Fail "$code/$($c.name): 상태 설정이 반영되지 않음 - $($probs -join ' / ')"
            } else {
                $diag = Invoke-Diag $code "${code}_$($c.name)"
                $ok = Test-Expect $diag $code $c.expect "$code/$($c.name)"
                $executed["$code|$($c.name)"] = $true
                if ($ok -and $def.Fix -and $def.Fix.From -eq $c.name) {
                    if ($hasFix) { Invoke-FixFlow $def $code $c.name $c.expect $st }
                    else { Add-Fail "${code}: Fix 를 선언했지만 auto/confirm 조치 스크립트가 없음(등급 $grade)" }
                }
                if ($ok -and $def.Chain -and $def.Chain.From -eq $c.name) { Invoke-ChainFlow $def $code }
            }
            Restore-Resources $saved
        }
    } catch {
        Add-Fail "${code}: 실행 중 예외 - $($_.Exception.Message) $($_.ScriptStackTrace)"
        if ($saved) { Restore-Resources $saved }
    }
    $snap2 = Get-Snap "$code 케이스 후"
    Compare-Snap $snap $snap2 $AlwaysSoft (@($AlwaysSoftLines) + $(if ($def.FirewallRulesHard) { @() } else { @('^(rule|port|addr)\|') })) "$code 케이스 후 원복"
    if (-not $snap2) { $snap2 = Get-Snap "$code 케이스 후(재시도)" }
    # 다음 항목의 기준은 이번 원복 후 상태(원복 실패가 다음 항목 결과로 번지지 않게 - 실패는 위에서 이미 기록)
    $snap = $snap2
    Write-Host ("  ({0:N0}초)" -f ((Get-Date) - $tc).TotalSeconds)
}

if (-not $Only) {
    foreach ($c in $cases) { if (-not $executed.ContainsKey("$($c.code)|$($c.name)")) { Add-Fail "실행되지 않은 케이스: $($c.code)/$($c.name)" } }
}
Write-Host ("총 {0:N0}초, 케이스 {1}건 중 실행 {2}건" -f ((Get-Date) - $t0).TotalSeconds, $cases.Count, $executed.Count)
if ($fail.Count -gt 0) {
    Write-Host "FAIL: $Category/cases ($($fail.Count)건)"
    $fail | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "PASS: $Category/cases"
exit 0
