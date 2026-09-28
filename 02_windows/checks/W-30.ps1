# W-30 (중) SNMP Community String 복잡성 설정
# 판단 기준(가이드 원문): 양호 = SNMP 미사용 또는 Community String이 public/private 이 아님
#                        취약 = 사용 중이며 public 또는 private 인 경우

$svc = Get-Service -Name "SNMP" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-30" -Status "GOOD" -Detail "SNMP 서비스가 설치되어 있지 않거나 중지 상태임"
}

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities"
try {
    $communities = Get-ItemProperty -Path $path -ErrorAction Stop
    $names = $communities.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Name }
} catch {
    $names = @()
}

if ($names.Count -eq 0) {
    return New-CheckResult -Code "W-30" -Status "VULN" -Detail "SNMP 구동 중이나 Community String 이 설정되어 있지 않음 (W-29 참고)"
}

$weak = $names | Where-Object { $_ -eq "public" -or $_ -eq "private" }
if ($weak.Count -eq 0) {
    return New-CheckResult -Code "W-30" -Status "GOOD" -Detail "Community String 이 기본값(public/private)이 아님" -Evidence "설정된 Community 개수: $($names.Count)"
} else {
    return New-CheckResult -Code "W-30" -Status "VULN" -Detail "Community String 이 기본값(public/private)으로 설정되어 있음" -Evidence ($weak -join ", ")
}
