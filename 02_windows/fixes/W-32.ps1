# W-32 (중) DNS 서비스 구동 점검 (동적 업데이트 설정) [fix: param]
# 값: zones=동적 업데이트를 '없음'으로 바꿀 DNS 영역 이름(쉼표 구분) - 진단 증적의 AllowUpdate≠0 영역 중 동적 업데이트가 필요 없는 것
# 변경: 지정 영역의 동적 업데이트(AllowUpdate)를 0(없음)으로 변경(WMI MicrosoftDNS_Zone) - 원래 값을 기록해 원복 시 되돌림
# 영향: 지정 영역에 클라이언트·DHCP·도메인 컨트롤러가 하던 동적 레코드 등록이 즉시 멈춤(AD 통합 영역이면 SRV 레코드 갱신 중단)
# 가이드 조치 방법: DNS 동적 업데이트 '없음'. 1.3.0 에 auto→manual 재분류했던 이유(도메인 컨트롤러의 AD SRV 레코드·클라이언트 등록이
# 끊김)대로 영역별 필요 여부는 사람이 판단한다 - 1.7.0 값 지정 조치로 운영자가 고른 영역만 바꾼다(guide.json deviation).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): DNS 서비스 구동 중·있는 영역·지금 AllowUpdate≠0·중복 없음.

$vals = @(Get-FixParam -Key "zones")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 W-32.zones 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$svc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "DNS 서버 서비스가 구동 중이 아니어서 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
try { $zones = @(Get-CimInstance -Namespace "root\MicrosoftDNS" -ClassName "MicrosoftDNS_Zone" -ErrorAction Stop) }
catch { $Global:FixStatus = "ERROR"; $Global:FixDetail = "MicrosoftDNS_Zone 조회 실패 - 바꾸지 않음: $($_.Exception.Message)"; $Global:FixEvidence = ""; return }
$errs = @(); $seen = @{}
foreach ($v in $vals) {
    if ($seen.ContainsKey($v.ToLowerInvariant())) { $errs += "${v}: 값에 두 번 나옴"; continue }
    $seen[$v.ToLowerInvariant()] = $true
    $z = @($zones | Where-Object { $_.Name -ieq $v })
    if ($z.Count -eq 0) { $errs += "${v}: 없는 영역"; continue }
    if ($z[0].AllowUpdate -eq 0) { $errs += "${v}: 이미 동적 업데이트 없음(0)" }
}
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

$done = @(); $failed = @()
foreach ($v in $vals) {
    try { Set-FixDnsZoneAllowUpdate -Zone $v -Value 0; $done += $v }
    catch {
        if ($_.Exception.Message.StartsWith("[백업 실패]")) { throw }
        $failed += "${v}($($_.Exception.Message))"
    }
}
$Global:FixEvidence = (@(Get-CimInstance -Namespace "root\MicrosoftDNS" -ClassName "MicrosoftDNS_Zone" -ErrorAction SilentlyContinue) |
        ForEach-Object { "$($_.Name): AllowUpdate=$($_.AllowUpdate)" }) -join "`n"
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "영역 동적 업데이트 변경 실패: $($failed -join ', ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 영역의 동적 업데이트를 '없음'(0)으로 설정: $($done -join ', ')"
}
