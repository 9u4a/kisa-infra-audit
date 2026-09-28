# W-31 (중) SNMP Access Control 설정
# 판단 기준(가이드 원문): 양호 = SNMP 미사용 또는 특정 호스트로만 SNMP 패킷 수신 설정
#                        취약 = 모든 호스트로부터 SNMP 패킷을 받아들이는 경우

$svc = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-31" -Status "GOOD" -Detail "SNMP 서비스가 설치되어 있지 않거나 중지 상태임"
}

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers"
try {
    $mgrs = Get-ItemProperty -Path $path -ErrorAction Stop
    $hosts = $mgrs.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object { $_.Value }
} catch {
    $hosts = @()
}

if ($hosts.Count -gt 0) {
    return New-CheckResult -Code "W-31" -Status "GOOD" -Detail "특정 호스트로부터의 SNMP 패킷만 허용하도록 설정됨" -Evidence ("허용 호스트: " + ($hosts -join ", "))
} else {
    return New-CheckResult -Code "W-31" -Status "VULN" -Detail "SNMP 패킷 수신 호스트 제한이 설정되어 있지 않음 (모든 호스트 허용)" -Evidence "$path 하위 값 없음"
}
