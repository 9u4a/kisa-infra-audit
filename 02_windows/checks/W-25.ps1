# W-25 (상) DNS Zone Transfer 설정
# 판단 기준(가이드 원문): 양호 = DNS 미사용, 영역 전송 미허용, 또는 특정 서버로만 제한
#                        취약 = 위 3가지 중 하나도 해당하지 않는 경우

$svc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-25" -Status "GOOD" -Detail "DNS 서버 서비스가 설치되어 있지 않거나 중지 상태임"
}

try {
    $zones = Get-CimInstance -Namespace "root\MicrosoftDNS" -ClassName "MicrosoftDNS_Zone" -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-25" -Status "MANUAL" -Detail "DNS 서비스는 구동 중이나 MicrosoftDNS WMI 네임스페이스를 조회하지 못함(DNS 서버 역할 미설치 가능) — dnsmgmt.msc 로 수동 확인 필요"
}

if (-not $zones) {
    return New-CheckResult -Code "W-25" -Status "NA" -Detail "DNS 서비스는 구동 중이나 등록된 영역(Zone)이 없음"
}

# SecureSecondaries: 0=모든 서버 허용(취약), 1=Notify 목록만, 2=SecondaryServers 목록만, 3=전송 안 함
$violations = $zones | Where-Object { $_.SecureSecondaries -eq 0 }
$evidence = ($zones | ForEach-Object { "$($_.Name): SecureSecondaries=$($_.SecureSecondaries)" }) -join "`n"

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-25" -Status "GOOD" -Detail "모든 영역의 Zone Transfer 가 제한되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-25" -Status "VULN" -Detail ("Zone Transfer 가 모든 서버에 허용된 영역 존재: " + (($violations | ForEach-Object { $_.Name }) -join ", ")) -Evidence $evidence
}
