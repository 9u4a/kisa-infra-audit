# W-20 (상) NetBIOS 바인딩 서비스 구동 점검
# 판단 기준(가이드 원문): 양호 = TCP/IP와 NetBIOS 바인딩이 제거된 경우 / 취약 = 제거되지 않은 경우
# TcpipNetbiosOptions: 0=DHCP 기본값(사용), 1=사용, 2=사용 안 함

try {
    $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-20" -Status "ERROR" -Detail "네트워크 어댑터 구성 조회 실패: $($_.Exception.Message)"
}

if (-not $adapters) {
    return New-CheckResult -Code "W-20" -Status "NA" -Detail "IP가 활성화된 네트워크 어댑터가 없음"
}

$enabled = $adapters | Where-Object { $_.TcpipNetbiosOptions -ne 2 }
$evidence = ($adapters | ForEach-Object { "$($_.Description): TcpipNetbiosOptions=$($_.TcpipNetbiosOptions)" }) -join "`n"

if ($enabled.Count -eq 0) {
    return New-CheckResult -Code "W-20" -Status "GOOD" -Detail "모든 활성 어댑터에서 NetBIOS over TCP/IP 가 사용 안 함으로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-20" -Status "VULN" -Detail "NetBIOS over TCP/IP 바인딩이 제거되지 않은 어댑터가 존재함" -Evidence $evidence
}
