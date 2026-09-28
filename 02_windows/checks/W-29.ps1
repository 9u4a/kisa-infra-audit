# W-29 (중) 불필요한 SNMP 서비스 구동 점검
# 판단 기준(가이드 원문): 양호 = SNMP 미사용 또는 Community String 설정 후 사용
#                        취약 = 불필요하게 사용(=미설정 상태로 방치)

$svc = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-29" -Status "GOOD" -Detail "SNMP 서비스가 설치되어 있지 않거나 중지 상태임"
}

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities"
try {
    $communities = Get-ItemProperty -Path $path -ErrorAction Stop
    $names = $communities.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Name }
} catch {
    $names = @()
}

if ($names.Count -gt 0) {
    return New-CheckResult -Code "W-29" -Status "GOOD" -Detail "SNMP 서비스가 Community String 설정과 함께 사용 중임 (복잡성은 W-30, 접근 제어는 W-31 참고)" -Evidence "설정된 Community 개수: $($names.Count)"
} else {
    return New-CheckResult -Code "W-29" -Status "VULN" -Detail "SNMP 서비스가 구동 중이나 Community String 이 설정되어 있지 않음" -Evidence "$path 하위 값 없음"
}
