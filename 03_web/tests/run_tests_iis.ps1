# 03_web/tests/run_tests_iis.ps1 [-Bootstrap]
# GitHub Actions windows-latest(휘발성 Windows Server VM, IIS·ARR 을 workflow 에서 설치)에서만 실행한다.
#   ① 전역 픽스처: fixtures/apply_iis.ps1 -Mode vuln|hardened(WEB-04 리스팅·WEB-18 WebDAV·WEB-12 정션을 가르고 준비 직후
#      실제 값을 다시 읽어 확인) → run.ps1(Windows PowerShell 5.1) → expected_iis_<mode>.json 비교. 기대값은 guide.json
#      판단기준으로 정한 값이다(러너 IIS 기본값에 대한 판단 근거는 아래 $Basis). -Bootstrap 은 차이만 출력한다(파일 미변경).
#   ② 항목별 케이스(fixtures/cases/cases.json 의 engine=iis + cases/iis_cases.ps1): 한 항목씩 취약/양호 상태를 만들고
#      판정 → (조치 스크립트가 있으면) 조치 → 재진단 → 원복 → 상태 비교 → 정리 → 상태 비교(lib/tests/win_case_runner.ps1).
#      선언된 케이스가 하나라도 실행되지 않으면 FAIL.
param([switch]$Bootstrap)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# 전역 픽스처에서 명시적으로 가르지 않는 항목의 기대값 근거(러너 IIS 기본 상태 → 가이드 판단기준):
#   WEB-07 VULN: 러너(Windows Server)에 MDAC msadc 기본 경로가 있음(가이드 "기본 생성 불필요 파일 존재")
#   WEB-11 VULN: Default Web Site 가 기본 경로 inetpub\wwwroot 사용(가이드 "분리되지 않은 경로")
#   WEB-15/19 VULN: Web-Includes 설치로 .stm/.shtm/.shtml SSI 매핑 존재(가이드 사례의 불필요 매핑/SSI 활성)
#   WEB-16 VULN: removeServerHeader 기본 false(Server 헤더 노출)   WEB-20/21 VULN: https 바인딩 없음
#   그 외 GOOD: IIS 기본값이 가이드 양호 기준(리스팅 off, CGI 목록 외 차단, parentPaths off, 업로드 30MB 제한,
#   ApplicationPoolIdentity, ARR 프록시 off, hiddenSegments web.config, 사이트·로그 경로 일반 사용자 쓰기 없음 등)
$fail = $false
foreach ($mode in @("vuln", "hardened")) {
    Write-Host "[*] IIS $mode 픽스처 적용..."
    & (Join-Path $ScriptDir "fixtures\apply_iis.ps1") -Mode $mode

    $outDir = Join-Path $env:TEMP "web03iis_$mode"
    Remove-Item -Recurse -Force $outDir -ErrorAction SilentlyContinue
    & powershell -NoProfile -File (Join-Path $RepoRoot "03_web\run.ps1") -OutBase $outDir *>$null

    $resultPath = Get-ChildItem -Path $outDir -Recurse -Filter result.json | Select-Object -First 1 -ExpandProperty FullName
    if (-not $resultPath) { Write-Host "FAIL: iis/$mode - result.json 을 찾지 못함"; $fail = $true; continue }
    $items = (Get-Content -Raw -Encoding UTF8 $resultPath | ConvertFrom-Json).items
    $actual = @{}
    foreach ($it in $items) { $actual[$it.code] = $it.status }

    $expectedPath = Join-Path $ScriptDir "fixtures\expected_iis_$mode.json"
    if (-not (Test-Path $expectedPath)) { Write-Host "FAIL: iis/$mode - $expectedPath 가 없음"; $fail = $true; continue }
    $expected = Get-Content -Raw $expectedPath | ConvertFrom-Json
    $failures = @()
    foreach ($prop in $expected.PSObject.Properties) {
        if ($actual[$prop.Name] -ne $prop.Value) { $failures += "$($prop.Name): 기대=$($prop.Value) 실제=$($actual[$prop.Name])" }
    }
    $failures += @($actual.Keys | Where-Object { -not $expected.PSObject.Properties[$_] } | ForEach-Object { "${_}: 기대값 없음(실제=$($actual[$_]))" })
    if ($Bootstrap) {
        # 기대값은 가이드 판단기준으로 사람이 정한다 - 차이만 보여 주고 파일은 바꾸지 않는다
        Write-Host "BOOTSTRAP(diff only): iis/$mode - 차이 $($failures.Count)건"
        $failures | ForEach-Object { Write-Host "  - $_" }
        $items | ForEach-Object { Write-Host ("  {0,-7} {1,-7} {2}" -f $_.code, $_.status, $_.detail) }
        continue
    }
    if ($failures.Count -gt 0) { Write-Host "FAIL: iis/$mode - $($failures.Count)건 불일치"; $failures | ForEach-Object { Write-Host "  - $_" }; $fail = $true }
    else { Write-Host "PASS: iis/$mode" }
}

# ② 항목별 케이스 - hardened 상태에서 한 항목씩
. (Join-Path $RepoRoot "lib\tests\win_case_runner.ps1")
. (Join-Path $ScriptDir "fixtures\cases\iis_cases.ps1")
$declared = Get-DeclaredCases -CasesJson (Join-Path $ScriptDir "fixtures\cases\cases.json") -Engine "iis"
$apphostFile = Join-Path $env:windir "system32\inetsrv\config\applicationHost.config"
$hash0 = (Get-FileHash -Algorithm SHA256 $apphostFile).Hash
$caseFail = Invoke-CaseSuite -Declared $declared -Impl $IisCases -Repo $RepoRoot -Category "03_web" -FixSubDir "fixes\iis" -Prelude $IisCasePrelude -Engine "iis"
if (@($caseFail).Count -gt 0) { Write-Host "FAIL: iis/cases"; $caseFail | ForEach-Object { Write-Host "  - $_" }; $fail = $true }
else { Write-Host "PASS: iis/cases ($(@($declared).Count)건)" }
# 모든 케이스 정리 뒤 applicationHost.config 가 케이스 시작 전과 같아야 한다(다음 workflow 단계가 같은 러너 상태를 쓴다)
if ((Get-FileHash -Algorithm SHA256 $apphostFile).Hash -ne $hash0) { Write-Host "FAIL: iis/cases - 케이스 정리 후 applicationHost.config 가 시작 전과 다름"; $fail = $true }

if ($fail) { exit 1 }
