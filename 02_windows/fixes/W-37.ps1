# W-37 (중) 예약된 작업에 의심스러운 명령이 등록되어 있는지 점검 [fix: param]
# 값: tasks=비활성화할 예약 작업 전체 경로(경로+이름, 예: \Vendor\Updater, 쉼표 구분) - 진단 증적의 사용자 정의 작업 중 불필요·의심 작업
# 변경: 지정 예약 작업 비활성화(Disable-ScheduledTask) - 삭제하지 않음(원복 시 다시 사용)
# 영향: 지정 예약 작업 실행 중단 — 그 작업이 하던 백업·배치·업데이트가 멈춤
# 가이드 조치 방법: 불필요한 예약 작업 제거. 의심 여부는 사람이 판단한다(진단은 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 있는 작업·\Microsoft\Windows\ 아래(OS 기본 작업)가 아님·지금 사용 중·중복 없음.

$vals = @(Get-FixParam -Key "tasks")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 W-37.tasks 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$errs = @(); $seen = @{}; $plan = @()
foreach ($v in $vals) {
    if ($seen.ContainsKey($v.ToLowerInvariant())) { $errs += "${v}: 값에 두 번 나옴"; continue }
    $seen[$v.ToLowerInvariant()] = $true
    $i = $v.LastIndexOf("\")
    if (-not $v.StartsWith("\") -or $i -lt 0 -or $i -eq $v.Length - 1) { $errs += "${v}: 작업 전체 경로 형식이 아님(\경로\이름)"; continue }
    $path = $v.Substring(0, $i + 1); $name = $v.Substring($i + 1)
    if ($path -like "\Microsoft\Windows\*") { $errs += "${v}: OS 기본 작업(\Microsoft\Windows\)은 자동으로 바꾸지 않음"; continue }
    try { $t = Invoke-CimCmdletWithTimeout -Command Get-ScheduledTask -Parameters @{ TaskPath = $path; TaskName = $name } -TimeoutSec 60 }
    catch { $errs += "${v}: 작업 조회 실패($($_.Exception.Message))"; continue }
    if (-not $t) { $errs += "${v}: 없는 작업"; continue }
    if ($t.State -eq "Disabled") { $errs += "${v}: 이미 비활성"; continue }
    $plan += [PSCustomObject]@{ Path = $path; Name = $name; Full = $v }
}
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

$done = @(); $failed = @()
foreach ($p in $plan) {
    try { [void](Disable-FixScheduledTask -TaskPath $p.Path -TaskName $p.Name); $done += $p.Full }
    catch {
        if ($_.Exception.Message.StartsWith("[백업 실패]")) { throw }
        $failed += "$($p.Full)($($_.Exception.Message))"
    }
}
$Global:FixEvidence = ($plan | ForEach-Object { $s = (Get-ScheduledTask -TaskPath $_.Path -TaskName $_.Name -ErrorAction SilentlyContinue).State; "$($_.Full) [$s]" }) -join "`n"
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "예약 작업 비활성화 실패: $($failed -join ', ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 예약 작업을 비활성화함: $($done -join ', ')"
}
