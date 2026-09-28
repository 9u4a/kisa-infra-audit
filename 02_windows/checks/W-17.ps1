# W-17 (상) 하드디스크 기본 공유 제거
# 판단 기준(가이드 원문): 양호 = AutoShareServer 가 0이며 기본 공유가 존재하지 않는 경우
#                        취약 = AutoShareServer 가 1이거나 기본 공유가 존재하는 경우

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
$auto = Test-RegistryValue -Path $path -Name "AutoShareServer"

try {
    $defaultShares = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -match '^[A-Za-z]\$$' -or $_.Name -eq 'ADMIN$' }
} catch {
    $defaultShares = @()
}

$evidence = "AutoShareServer=$auto`n기본 공유: " + (($defaultShares | ForEach-Object { $_.Name }) -join ", ")

if ($auto -eq 0 -and (-not $defaultShares -or $defaultShares.Count -eq 0)) {
    return New-CheckResult -Code "W-17" -Status "GOOD" -Detail "AutoShareServer=0 이며 기본(관리용) 공유가 존재하지 않음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-17" -Status "VULN" -Detail "AutoShareServer 가 0이 아니거나 기본(관리용) 공유가 존재함" -Evidence $evidence
}
