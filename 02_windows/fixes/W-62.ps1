# W-62 (중) 시작 프로그램 목록 분석 [fix: param]
# 값: entries=제거할 시작 프로그램 이름(쉼표 구분) - 진단 증적("이름 | 명령 | 위치")의 이름 중 불필요·의심 항목. 레지스트리 Run 키 항목만
# 변경: 지정 시작 프로그램의 레지스트리 Run 값 제거(값을 백업해 원복 시 되살림) - 프로그램 파일은 지우지 않음
# 영향: 지정 프로그램이 다음 로그온·부팅부터 자동 실행되지 않음(에이전트·트레이 프로그램이면 그 기능이 멈춤)
# 가이드 조치 방법: 불필요한 시작 프로그램 비활성화. 필요 여부는 사람이 판단한다(진단은 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): Win32_StartupCommand 에 그 이름이 정확히 하나·위치가 레지스트리(HKLM·HKU)·중복 없음.
# 시작 폴더(Startup·Common Startup)의 바로가기는 사용자 프로필 파일이라 자동으로 지우지 않는다(값에 있으면 거부, 수동 조치).

$vals = @(Get-FixParam -Key "entries")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 W-62.entries 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
try { $items = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop) }
catch { $Global:FixStatus = "ERROR"; $Global:FixDetail = "시작 프로그램 목록 조회 실패 - 바꾸지 않음: $($_.Exception.Message)"; $Global:FixEvidence = ""; return }
$errs = @(); $seen = @{}; $plan = @()
foreach ($v in $vals) {
    if ($seen.ContainsKey($v.ToLowerInvariant())) { $errs += "${v}: 값에 두 번 나옴"; continue }
    $seen[$v.ToLowerInvariant()] = $true
    $m = @($items | Where-Object { $_.Name -ceq $v })
    if ($m.Count -eq 0) { $errs += "${v}: 시작 프로그램 목록에 없음"; continue }
    if ($m.Count -gt 1) { $errs += "${v}: 같은 이름이 $($m.Count)곳에 있음(위치: $(($m | ForEach-Object { $_.Location }) -join ', ')) - 수동 조치"; continue }
    $loc = "$($m[0].Location)"
    $root = switch -Regex ($loc) { '^HKLM\\' { "HKEY_LOCAL_MACHINE" } '^HKU\\' { "HKEY_USERS" } default { "" } }
    if (-not $root) { $errs += "${v}: 레지스트리 Run 항목이 아님(위치 $loc) - 시작 폴더 바로가기는 수동 조치"; continue }
    $path = "Registry::$root\" + $loc.Substring($loc.IndexOf("\") + 1)
    if ($null -eq (Get-ItemProperty -LiteralPath $path -Name $v -ErrorAction SilentlyContinue)) { $errs += "${v}: $loc 에서 값을 찾지 못함"; continue }
    $plan += [PSCustomObject]@{ Name = $v; Path = $path; Location = $loc }
}
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

$done = @(); $failed = @()
foreach ($p in $plan) {
    Remove-FixRegistryValue -Path $p.Path -Name $p.Name
    if ($null -eq (Get-ItemProperty -LiteralPath $p.Path -Name $p.Name -ErrorAction SilentlyContinue)) { $done += "$($p.Name)($($p.Location))" } else { $failed += $p.Name }
}
$Global:FixEvidence = ($done -join "`n")
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "시작 프로그램 제거 실패: $($failed -join ', ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 시작 프로그램의 Run 값을 제거함: $($done -join ', ')"
}
