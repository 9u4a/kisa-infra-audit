# W-32 (중) DNS 서비스 구동 점검 (동적 업데이트 설정)
# 판단 기준(가이드 원문): 양호 = DNS 미사용 또는 동적 업데이트 "없음" / 취약 = 동적 업데이트 설정됨
# AllowUpdate: 0=None(없음) 1=NonsecureAndSecure 2=SecureOnly(AD 통합)

$svc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-32" -Status "GOOD" -Detail "DNS 서버 서비스가 설치되어 있지 않거나 중지 상태임"
}

try {
    $zones = Get-CimInstance -Namespace "root\MicrosoftDNS" -ClassName "MicrosoftDNS_Zone" -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-32" -Status "MANUAL" -Detail "DNS 서비스는 구동 중이나 MicrosoftDNS WMI 네임스페이스를 조회하지 못함 — dnsmgmt.msc 로 수동 확인 필요"
}

if (-not $zones) {
    return New-CheckResult -Code "W-32" -Status "NA" -Detail "DNS 서비스는 구동 중이나 등록된 영역(Zone)이 없음"
}

$violations = $zones | Where-Object { $_.AllowUpdate -ne 0 }
$evidence = ($zones | ForEach-Object { "$($_.Name): AllowUpdate=$($_.AllowUpdate)" }) -join "`n"

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-32" -Status "GOOD" -Detail "모든 영역의 동적 업데이트가 없음(0)으로 설정됨" -Evidence $evidence
} else {
    # 1.7.0 값 지정 조치: W-32.zones 후보(동적 업데이트가 켜진 영역) - lib/policy_draft.py 가 읽는다
    $cand = @($violations | ForEach-Object { "$($_.Name)" } | Where-Object { $_ -notmatch ',' })
    if ($cand.Count -gt 0) { $evidence += "`n`n[candidates] $($cand -join ',')" }
    return New-CheckResult -Code "W-32" -Status "VULN" -Detail ("동적 업데이트가 설정된 영역 존재: " + (($violations | ForEach-Object { $_.Name }) -join ", ")) -Evidence $evidence
}
