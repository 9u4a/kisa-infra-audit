# lib/tests/fix_safety_windows.ps1 -Category <02_windows|07_pc|03_web>
# Windows 계열 조치(fix.ps1)의 운영 안전 회귀 테스트. GitHub Actions windows-latest(휘발성 Windows Server
# VM)에서만 실행한다 - 실제 보안 정책·레지스트리·서비스·IIS 설정을 바꾼다. 로컬 개발자 PC에서는 실행 금지.
#   ① 진단 → ② fix.ps1 -Apply -Yes(비대화형: confirm 등급은 확인 단계에서 건너뜀, auto 만 적용)
#   → ③ 재진단: 적용된 항목이 VULN/ERROR 를 벗어났는가 → ④ fix.ps1 -Rollback
#   → ⑤ 재진단: 적용된 항목의 판정이 조치 전과 같은가(원복 불가로 보고된 항목은 경고로만 표시)
#   → ⑥ 반드시 적용돼야 하는 항목($MustApply): 픽스처가 VULN 을 만들었고 조치가 APPLIED 로 끝났는가
#      (예전에는 "재검증 실패 → 원복(FAILED_ROLLED_BACK)"이 테스트 실패가 아니어서 조치가 진단을 못 따라가도 통과했다)
#   → ⑦ 재현 케이스($Cases): 준비 스크립트로 취약 상태를 만든 뒤 한 항목씩 검사하고 정리 스크립트로 되돌린다.
#      direct = confirm 등급(비대화형 fix.ps1 로는 적용되지 않음)을 fix.ps1 과 같은 방식(공통 모듈·백업 폴더·
#               $Global:FixCode)으로 직접 실행 → 재진단 GOOD 류 → fix.ps1 -Rollback → 재진단이 조치 전(VULN)과 같은가
#      manual = fix.ps1 -Apply -Yes 가 그 항목을 MANUAL 로만 기록하고 아무것도 바꾸지 않는가
# 확인 질문은 파이프 입력으로 비대화형을 만들어(Test-FixInteractive) CI 가 입력 대기로 멈추지 않게 한다.
param([Parameter(Mandatory = $true)][ValidateSet("02_windows", "07_pc", "03_web")][string]$Category)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$runPs1 = Join-Path $Repo "$Category\run.ps1"
$fixPs1 = Join-Path $Repo "$Category\fix.ps1"
$CategoryNum = $Category.Substring(0, 2)
$FixSubDir = if ($Category -eq "03_web") { "fixes\iis" } else { "fixes" }
. (Join-Path $PSScriptRoot "win_state_snapshot.ps1")

function Invoke-Diag([string]$Tag, [string]$Items = "") {
    $out = Join-Path $env:TEMP "fs_${Category}_$Tag"
    Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    if ($Items) { & powershell -NoProfile -NonInteractive -File $runPs1 -Items $Items -OutBase $out *>$null }
    else { & powershell -NoProfile -NonInteractive -File $runPs1 -OutBase $out *>$null }
    $path = Get-ChildItem -Path $out -Recurse -Filter result.json | Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { throw "$Tag 진단 결과(result.json)를 찾지 못함" }
    $map = @{}; $detail = @{}
    foreach ($it in (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json).items) { $map[$it.code] = $it.status; $detail[$it.code] = $it.detail }
    return @{ Path = $path; Map = $map; Detail = $detail }
}

function Read-ChangesLog([string]$RunDir) {
    $logLines = Get-Content -Encoding UTF8 (Join-Path $RunDir "changes.log") | Where-Object { $_ -and -not $_.StartsWith("#") }
    return @($logLines | ForEach-Object { $c = $_ -split "`t"; [PSCustomObject]@{ Code = $c[1]; Grade = $c[2]; Result = $c[3]; Detail = ($c[4..($c.Count - 1)] -join " ") } })
}

function Invoke-Child([string]$Script) {
    <# 준비/정리/직접 적용 스크립트를 새 Windows PowerShell 프로세스에서 실행(모듈·IIS 스키마 캐시를 이 프로세스와 분리).
       종료 코드 0 이면 Ok. 자식의 stderr 가 이 프로세스의 Stop 설정에 걸려 예외가 되지 않도록 여기서만 Continue #>
    $ErrorActionPreference = "Continue"
    $full = "try {`n$Script`n} catch { Write-Output (""CHILD ERROR: "" + `$_.Exception.Message); exit 1 }`nexit 0"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    $out = & powershell -NoProfile -NonInteractive -EncodedCommand $enc 2>&1 | ForEach-Object { "$_" } | Out-String
    return @{ Ok = ($LASTEXITCODE -eq 0); Out = $out.Trim() }
}

$fail = @()
$GuideByCode = @{}
foreach ($it in (Get-Content -Raw -Encoding UTF8 (Join-Path $Repo "$Category\guide.json") | ConvertFrom-Json).items) { $GuideByCode[$it.code] = $it }

# 원복 불가로 보고된 조치가 바꾸는 상태 영역(실제 상태 비교에서 그 영역 차이는 참고로만). 여기 없는 코드가 원복 불가로
# 보고되면 영역을 알 수 없으므로 전체 비교를 참고로 낮추고 그 사실을 표시한다(새 Register-FixNoRollback 추가 시 여기도 갱신).
$NoRbAreas = @{ "W-17" = @("shares"); "PC-04" = @("shares"); "W-40" = @("audit"); "WEB-13" = @("iis"); "WEB-19" = @("iis"); "W-25" = @(); "W-34" = @(); "W-39" = @(); "PC-13" = @() }
$NoRbLines = @{ "W-42" = @('\\Services\\EventLog\\') }
# 항상 참고로만 보는 영역: iis(원복이 같은 값을 명시적으로 다시 써 파일 해시가 달라질 수 있음 - 의미 비교는 진단 판정으로),
# 임시 폴더: 실행 계정 TEMP(U|)에 조치가 남긴 파일은 실패(운영 서버 찌꺼기 - secedit /db 의 .jfm 을 CI 에서 실측),
# Windows\Temp(W|)는 Defender 엔진 업데이트 등 OS 활동이 수시로 쓰므로(CI 실측) 참고로만
$AlwaysSoft = @("iis")
$AlwaysSoftLines = @('^W\|')
# 카테고리별 최소 적용 건수(러너 기본 상태 + 픽스처 기준). 0건이면 이후 비교가 모두 비어 PASS 하던 것을 막는다.
$MinApplied = @{ "02_windows" = 1; "07_pc" = 1; "03_web" = 4 }
# auto 등급인데 러너에서 적용되지 않는 것이 알려진 항목(사유와 함께 추가). 비어 있으면 "VULN 인 auto 항목은 전부 APPLIED" 가 기준.
$KnownAutoNotApplied = @{
    # KNOWN_ISSUES L-06: 러너(Windows Server)의 Defender 실시간 감시는 Set-MpPreference 로 켜지지 않는다(정책/이미지 설정) -
    # 조치는 재검증 실패 → 원복(FAILED_ROLLED_BACK) 경로만 확인된다
    "PC-14" = "러너에서 Defender 실시간 감시를 켤 수 없음(KNOWN_ISSUES L-06)"
}

# RemoteRegistry 는 유휴 시 스스로 멈추는 서비스다 - 기준 진단(VULN: 구동 중)과 조치 사이에 멈추면 조치는 바꿀 것이 없어(NA) 백업도
# 없고, 원복 후 판정이 GOOD 이 되어 "원복 후 판정이 조치 전과 다름"으로 실패했다(CI run 41009395247, 07_pc PC-05 - 조치·원복 결함
# 아님). 02_windows/tests/fixtures/apply.ps1 과 같이 유휴 중지를 끄고 구동해 기준 상태를 결정적으로 만든다(스냅샷은 그 뒤에 뜬다).
if ($Category -in @("02_windows", "07_pc")) {
    $rrp = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters"
    if (-not (Test-Path $rrp)) { New-Item -Path $rrp | Out-Null }   # -Force 는 기존 키(ServiceDll)를 덮어쓴다
    Set-ItemProperty -Path $rrp -Name DisableIdleStop -Type DWord -Value 1
    if ((Get-Service -Name RemoteRegistry).StartType -eq "Disabled") { Set-Service -Name RemoteRegistry -StartupType Manual }
    Start-Service -Name RemoteRegistry
}

$base = Invoke-Diag "base"
$state0 = Get-WinStateSnapshot -Category $Category

$fixOut = Join-Path $env:TEMP "fs_${Category}_fix"
Remove-Item -Recurse -Force $fixOut -ErrorAction SilentlyContinue

# X-06: 다른 호스트의 result.json 으로는 -Apply -Yes 라도 아무것도 바꾸지 않고 exit 2 여야 한다
$foreign = Join-Path $env:TEMP "fs_${Category}_foreign.json"
$fj = Get-Content -Raw -Encoding UTF8 $base.Path | ConvertFrom-Json
$fj.host = "OTHER-HOST-X06"
$fj | ConvertTo-Json -Depth 6 | Out-File -FilePath $foreign -Encoding utf8
$foreignOut = Join-Path $env:TEMP "fs_${Category}_foreign_out"
$fLog = "" | & powershell -NoProfile -NonInteractive -File $fixPs1 -ResultJson $foreign -OutBase $foreignOut -Apply -Yes 2>&1 | Out-String
$fRc = $LASTEXITCODE
if ($fRc -ne 2 -or (Test-Path $foreignOut)) { $fail += "X-06: 다른 호스트 result.json 으로 적용이 거부되지 않음(exit=$fRc)`n$fLog" }
else { Write-Host "[$Category] X-06 다른 호스트 결과 거부 확인(exit 2, 출력 폴더 없음)" }
Remove-Item -Force $foreign -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $foreignOut -ErrorAction SilentlyContinue

$applyLog = "" | & powershell -NoProfile -NonInteractive -File $fixPs1 -ResultJson $base.Path -OutBase $fixOut -Apply -Yes 2>&1 | Out-String
$runDir = Get-ChildItem -Path $fixOut -Directory | Select-Object -First 1 -ExpandProperty FullName
if (-not $runDir) { throw "조치 출력 폴더를 찾지 못함:`n$applyLog" }
$rows = Read-ChangesLog $runDir
$applied = @($rows | Where-Object Result -eq "APPLIED" | ForEach-Object Code)
Write-Host "[$Category] 적용 결과: " (($rows | Group-Object Result | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ", ")
$rows | Where-Object { $_.Result -like "FAILED*" -or $_.Result -eq "ABORTED" -or $_.Result -eq "SKIPPED" } | ForEach-Object { Write-Host "  $($_.Code) $($_.Result): $($_.Detail)" }
if ($applyLog -match '\[백업 실패\]' -or ($rows | Where-Object Result -eq "ABORTED")) { $fail += "백업 실패로 중단됨" }
if ($rows | Where-Object Result -eq "FAILED_NOT_ROLLED_BACK") { $fail += "적용 실패 후 되돌리지 못한 항목 있음" }
if ($applied.Count -lt $MinApplied[$Category]) { $fail += "적용된 항목이 $($applied.Count)건 - 최소 $($MinApplied[$Category])건 기대(적용 0건이면 이후 비교가 비어 통과하게 됨)" }
# 조치 전 VULN 이던 auto 등급 항목은 모두 APPLIED 여야 한다(FAILED_ROLLED_BACK·SKIPPED·기록 없음 = 조치가 진단을 따라가지 못함)
foreach ($c in @($base.Map.Keys | Where-Object { $base.Map[$_] -eq "VULN" -and $GuideByCode[$_] -and $GuideByCode[$_].fix -eq "auto" } | Sort-Object)) {
    if ($applied -contains $c) { continue }
    $r = $rows | Where-Object Code -eq $c | Select-Object -First 1
    $why = if ($r) { "$($r.Result): $($r.Detail)" } else { "changes.log 기록 없음" }
    if ($KnownAutoNotApplied.ContainsKey($c)) { Write-Host "  알려진 미적용: $c ($($KnownAutoNotApplied[$c])) - $why" }
    else { $fail += "${c}: auto 등급·조치 전 VULN 인데 APPLIED 가 아님($why)" }
}

$after = Invoke-Diag "after"
foreach ($c in $applied) {
    $st = $after.Map[$c]
    if (-not $st) { $fail += "${c}: 적용 후 진단 결과에 항목이 없음"; continue }
    if ($st -eq "GOOD") { continue }
    if ($st -eq "NA") { Write-Host "  참고: ${c} 적용 후 NA($($after.Detail[$c]))"; continue }
    # 자동 판정이 부분(partial)인 항목은 조치 후에도 GOOD 에 닿지 못하도록 설계된 경우가 있어 MANUAL 을 허용(참고 표시)
    if ($st -eq "MANUAL" -and $GuideByCode[$c] -and $GuideByCode[$c].automation -ne "auto") { Write-Host "  참고: ${c} 적용 후 MANUAL(자동 판정 $($GuideByCode[$c].automation))"; continue }
    $fail += "${c}: 적용 후 판정이 GOOD 이 아님($($st): $($after.Detail[$c]))"
}

$rbLog = "" | & powershell -NoProfile -NonInteractive -File $fixPs1 -Rollback $runDir 2>&1 | Out-String
$noRb = @([regex]::Matches($rbLog, '원복 일부 실패/불가: (\S+)') | ForEach-Object { $_.Groups[1].Value })
$rb = Invoke-Diag "rollback"
$state2 = Get-WinStateSnapshot -Category $Category
foreach ($c in $applied) {
    if ($rb.Map[$c] -ne $base.Map[$c]) {
        if ($noRb -contains $c) { Write-Host "  경고: ${c} 원복 불가로 보고됨(조치 전 $($base.Map[$c]) → 원복 후 $($rb.Map[$c]))" }
        else { $fail += "${c}: 원복 후 판정이 조치 전과 다름(전 $($base.Map[$c]) / 후 $($rb.Map[$c]))" }
    }
}
if ($noRb.Count -gt 0) { Write-Host "  원복 불가로 보고된 항목: $($noRb -join ', ')" }
# 판정 비교만으로는 "원복 후 실제 값이 조치 전과 같은지"를 알 수 없다(예: 값 2 → 조치 1 → 원복이 0 으로 써도 둘 다 VULN).
# 조치 전·원복 후 실제 상태(서비스·레지스트리·보안/감사 정책·방화벽·공유·계정·예약 작업)를 비교한다.
$softAreas = @($AlwaysSoft); $softLines = @($AlwaysSoftLines)
foreach ($c in $noRb) {
    if ($NoRbAreas.ContainsKey($c)) { $softAreas += $NoRbAreas[$c] }
    elseif ($NoRbLines.ContainsKey($c)) { $softLines += $NoRbLines[$c] }
    else {
        Write-Host "  경고: 원복 불가 항목 $c 의 상태 영역을 몰라 실제 상태 비교 전체를 참고로만 표시(`$NoRbAreas 갱신 필요)"
        $softAreas += @($state0.Keys)
    }
}
$cmp = Compare-WinStateSnapshot -Before $state0 -After $state2 -SoftAreas $softAreas -SoftLinePatterns $softLines -Label "원복"
$fail += $cmp.Fail
$cmp.Notes | ForEach-Object { Write-Host "  · $_" }

# ⑥ 반드시 적용돼야 하는 항목 - 03_web: workflow 가 apply_iis.ps1 -Mode vuln -FixCases 로 하위 application/vdir·사이트
# 재정의까지 취약하게 만든다(F-R3). 루트·전역만 고치는 조치는 여기서 FAILED_ROLLED_BACK 으로 잡힌다.
$MustApply = @{ "03_web" = @("WEB-04", "WEB-16", "WEB-18", "WEB-22") }
if ($MustApply.ContainsKey($Category)) {
    foreach ($c in $MustApply[$Category]) {
        if ($base.Map[$c] -ne "VULN") { $fail += "${c}: 조치 전 진단이 VULN 이 아님($($base.Map[$c])) - 픽스처가 재현 상태를 만들지 못함"; continue }
        if ($applied -notcontains $c) {
            $r = $rows | Where-Object Code -eq $c | Select-Object -First 1
            $fail += "${c}: 조치가 APPLIED 로 끝나지 않음($(if ($r) { "$($r.Result): $($r.Detail)" } else { '기록 없음' }))"
        }
    }
}

# ⑦ 재현 케이스. Prepare/Cleanup 은 새 프로세스에서 실행되는 스크립트 텍스트(실패 시 throw).
$Cases = @()
if ($Category -eq "02_windows") {
    # F-R1: 진단은 LanmanServer\Parameters(정책의 실제 위치)와 예전 위치 Lsa 를 함께 본다 - 둘 다 0 으로 만든다
    $Cases += @{ Name = "W-23 SMB Null Session(LanmanServer + Lsa)"; Code = "W-23"; Expect = "direct"; Prepare = @'
$ErrorActionPreference = 'Stop'
$svc = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') { throw 'FTPSVC is running - the SMB branch of W-23 cannot be exercised' }
$st = @{}
foreach ($p in @('HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters', 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa')) {
    $st[$p] = (Get-ItemProperty -Path $p -Name RestrictNullSessAccess -ErrorAction SilentlyContinue).RestrictNullSessAccess
    New-ItemProperty -Path $p -Name RestrictNullSessAccess -PropertyType DWord -Value 0 -Force | Out-Null
}
$st | ConvertTo-Json | Set-Content -Path (Join-Path $env:TEMP 'kisa_case_w23_smb.json') -Encoding UTF8
'@; Cleanup = @'
$ErrorActionPreference = 'Stop'
$st = Get-Content -Raw -Path (Join-Path $env:TEMP 'kisa_case_w23_smb.json') | ConvertFrom-Json
foreach ($prop in $st.PSObject.Properties) {
    if ($null -eq $prop.Value) { Remove-ItemProperty -Path $prop.Name -Name RestrictNullSessAccess -ErrorAction SilentlyContinue }
    else { New-ItemProperty -Path $prop.Name -Name RestrictNullSessAccess -PropertyType DWord -Value ([int]$prop.Value) -Force | Out-Null }
}
'@ }
    # F-R1: FTP 구동 중 - 사이트 명시 값 true(kisa_ftp_explicit)와 siteDefaults 상속 true(kisa_ftp_inherit)
    $Cases += @{ Name = "W-23 FTP 익명 인증(사이트 명시 + siteDefaults 상속)"; Code = "W-23"; Expect = "direct"; Prepare = @'
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) { throw 'Install-WindowsFeature is not available (not Windows Server)' }
if (-not (Get-WindowsFeature Web-Ftp-Server).Installed) { Install-WindowsFeature Web-Ftp-Server | Out-Null }
Set-Service -Name FTPSVC -StartupType Manual
Start-Service -Name FTPSVC
Import-Module WebAdministration
$root = Join-Path $env:SystemDrive 'kisa_ftpcase'
$apphost = 'MACHINE/WEBROOT/APPHOST'
$anon = 'ftpServer/security/authentication/anonymousAuthentication'
$port = 2121
foreach ($n in @('kisa_ftp_inherit', 'kisa_ftp_explicit')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $n) | Out-Null
    New-WebFtpSite -Name $n -Port $port -PhysicalPath (Join-Path $root $n) -Force | Out-Null
    $port++
}
$orig = (Get-WebConfigurationProperty -PSPath $apphost -Filter "system.applicationHost/sites/siteDefaults/$anon" -Name enabled).Value
@{ SiteDefaults = [bool]$orig } | ConvertTo-Json | Set-Content -Path (Join-Path $env:TEMP 'kisa_case_w23_ftp.json') -Encoding UTF8
Set-WebConfigurationProperty -PSPath $apphost -Filter "system.applicationHost/sites/siteDefaults/$anon" -Name enabled -Value $true
Set-WebConfigurationProperty -PSPath $apphost -Filter "system.applicationHost/sites/site[@name='kisa_ftp_explicit']/$anon" -Name enabled -Value $true
'@; Cleanup = @'
$ErrorActionPreference = 'Stop'
Import-Module WebAdministration
foreach ($n in @('kisa_ftp_inherit', 'kisa_ftp_explicit')) { if (Get-Website | Where-Object { $_.Name -eq $n }) { Remove-Website -Name $n } }
$st = Get-Content -Raw -Path (Join-Path $env:TEMP 'kisa_case_w23_ftp.json') | ConvertFrom-Json
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/ftpServer/security/authentication/anonymousAuthentication' -Name enabled -Value ([bool]$st.SiteDefaults)
Stop-Service -Name FTPSVC -Force
Set-Service -Name FTPSVC -StartupType Disabled
Remove-Item -Recurse -Force -Path (Join-Path $env:SystemDrive 'kisa_ftpcase')
'@ }
}
if ($Category -eq "07_pc") {
    # F-R2: 설치 흔적(제거 목록)만 있는 상용 메신저 - 조치는 manual(삭제는 자동화하지 않음)이어야 한다
    $Cases += @{ Name = "PC-06 설치된 상용 메신저(제거 목록)"; Code = "PC-06"; Expect = "manual"; Prepare = @'
$ErrorActionPreference = 'Stop'
$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\KisaFixCaseMessenger'
New-Item -Path $k -Force | Out-Null
New-ItemProperty -Path $k -Name DisplayName -PropertyType String -Value 'Slack (kisa fix case)' -Force | Out-Null
'@; Cleanup = @'
$ErrorActionPreference = 'Stop'
Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\KisaFixCaseMessenger' -Recurse -Force
'@ }
}

$n = 0
foreach ($case in $Cases) {
    $n++
    $code = $case.Code
    Write-Host "[$Category] 재현 케이스 $n - $($case.Name)"
    $prep = Invoke-Child $case.Prepare
    if (-not $prep.Ok) { $fail += "$($case.Name): 준비 실패 - $($prep.Out)"; Invoke-Child $case.Cleanup | Out-Null; continue }
    try {
        $pre = Invoke-Diag "case${n}_pre" $code
        if ($pre.Map[$code] -ne "VULN") { $fail += "$($case.Name): 준비 후 진단이 VULN 이 아님($($pre.Map[$code]): $($pre.Detail[$code]))"; continue }

        if ($case.Expect -eq "manual") {
            $mOut = Join-Path $env:TEMP "fs_${Category}_case${n}_fix"
            Remove-Item -Recurse -Force $mOut -ErrorAction SilentlyContinue
            $mLog = "" | & powershell -NoProfile -NonInteractive -File $fixPs1 -ResultJson $pre.Path -Items $code -OutBase $mOut -Apply -Yes 2>&1 | Out-String
            $mDir = Get-ChildItem -Path $mOut -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            $mRow = if ($mDir) { Read-ChangesLog $mDir | Where-Object Code -eq $code | Select-Object -First 1 } else { $null }
            if (-not $mRow -or $mRow.Result -ne "MANUAL") { $fail += "$($case.Name): fix.ps1 이 MANUAL 로 기록하지 않음($(if ($mRow) { $mRow.Result } else { '기록 없음' }))`n$mLog" }
            $post = Invoke-Diag "case${n}_post" $code
            if ($post.Map[$code] -ne "VULN") { $fail += "$($case.Name): manual 항목인데 조치 후 판정이 바뀜(VULN → $($post.Map[$code]))" }
            else { Write-Host "  manual 확인: 변경 없음(VULN 유지)" }
            continue
        }

        # direct: fix.ps1 과 같은 준비(공통 모듈·백업 폴더·$Global:FixCode)로 조치 스크립트 하나를 실행
        $dOut = Join-Path $env:TEMP "fs_${Category}_case${n}_fix"
        Remove-Item -Recurse -Force $dOut -ErrorAction SilentlyContinue
        $cs0 = Get-WinStateSnapshot -Category $Category
        $sq ={ param($s) $s -replace "'", "''" }
        $direct = @'
$ErrorActionPreference = 'Continue'
Import-Module '__LIB__' -Force
New-FixOutputDir -BaseDir '__OUT__' -CategoryNum '__NUM__' | Out-Null
$Global:FixCode = '__CODE__'
$Global:FixStatus = 'ERROR'; $Global:FixDetail = 'no result from fix script'; $Global:FixEvidence = ''
try { & '__FIX__' } catch { $Global:FixStatus = 'ERROR'; $Global:FixDetail = 'exception: ' + $_.Exception.Message }
Write-Output ('DIRECTFIX|' + $Global:FixStatus + '|' + $Global:FixDetail)
'@
        $direct = $direct.Replace("__LIB__", (& $sq (Join-Path $Repo "lib\Common.psm1"))).Replace("__OUT__", (& $sq $dOut)).Replace("__NUM__", $CategoryNum).Replace("__CODE__", $code).Replace("__FIX__", (& $sq (Join-Path $Repo "$Category\$FixSubDir\$code.ps1")))
        $d = Invoke-Child $direct
        $m = [regex]::Match($d.Out, 'DIRECTFIX\|([^|]*)\|(.*)')
        $dStatus = if ($m.Success) { $m.Groups[1].Value } else { "?" }
        Write-Host "  조치: $dStatus $(if ($m.Success) { $m.Groups[2].Value })"
        if ($dStatus -ne "APPLIED") { $fail += "$($case.Name): 조치 결과가 APPLIED 가 아님($dStatus)`n$($d.Out)" }
        $post = Invoke-Diag "case${n}_post" $code
        if ($post.Map[$code] -in @("VULN", "ERROR")) { $fail += "$($case.Name): 조치 후에도 $($post.Map[$code]) ($($post.Detail[$code]))" }
        $dRun = Get-ChildItem -Path $dOut -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if (-not $dRun) { $fail += "$($case.Name): 조치 출력 폴더 없음"; continue }
        $dRb = "" | & powershell -NoProfile -NonInteractive -File $fixPs1 -Rollback $dRun 2>&1 | Out-String
        if ($dRb -match '원복 일부 실패/불가') { $fail += "$($case.Name): 원복 일부 실패/불가`n$dRb" }
        $back = Invoke-Diag "case${n}_rollback" $code
        if ($back.Map[$code] -ne $pre.Map[$code]) { $fail += "$($case.Name): 원복 후 판정이 조치 전과 다름(전 $($pre.Map[$code]) / 후 $($back.Map[$code]): $($back.Detail[$code]))" }
        else { Write-Host "  적용 → $($post.Map[$code]), 원복 → $($back.Map[$code]) (조치 전과 같음)" }
        if ($post.Map[$code] -ne "GOOD" -and $post.Map[$code] -notin @("VULN", "ERROR")) { $fail += "$($case.Name): 조치 후 판정이 GOOD 이 아님($($post.Map[$code]))" }
        # 판정뿐 아니라 실제 값(레지스트리 등)이 준비 직후 상태로 돌아왔는지 - iis 는 같은 값을 명시적으로 다시 써 해시가 달라질 수
        # 있어 참고로만(의미 비교는 위 진단 판정)
        $cs2 = Get-WinStateSnapshot -Category $Category
        $ccmp = Compare-WinStateSnapshot -Before $cs0 -After $cs2 -SoftAreas $AlwaysSoft -SoftLinePatterns $AlwaysSoftLines -Label "$($case.Name) 원복"
        $fail += $ccmp.Fail
        $ccmp.Notes | ForEach-Object { Write-Host "  · $_" }
    } finally {
        $cl = Invoke-Child $case.Cleanup
        if (-not $cl.Ok) { $fail += "$($case.Name): 정리 실패 - $($cl.Out)" }
    }
}
if ($Cases.Count -gt 0) {
    # 정리 후 원래 판정으로 돌아왔는지(다음 workflow 단계가 같은 러너 상태를 쓴다) - 경고만
    $codes = @($Cases | ForEach-Object { $_.Code } | Sort-Object -Unique)
    $end = Invoke-Diag "cases_end" ($codes -join ",")
    foreach ($c in $codes) { if ($end.Map[$c] -ne $base.Map[$c]) { Write-Host "  경고: 재현 케이스 정리 후 ${c} 판정이 처음과 다름(처음 $($base.Map[$c]) / 지금 $($end.Map[$c]))" } }
}

if ($fail.Count -gt 0) {
    Write-Host "FAIL: $Category/fix-safety"; $fail | ForEach-Object { Write-Host "  - $_" }
    Write-Host "----- apply log -----"; Write-Host $applyLog; Write-Host "----- rollback log -----"; Write-Host $rbLog
    exit 1
}
Write-Host "PASS: $Category/fix-safety (적용 $($applied.Count)건: $($applied -join ', ')$(if ($Cases.Count) { " / 재현 케이스 $($Cases.Count)건" }))"
