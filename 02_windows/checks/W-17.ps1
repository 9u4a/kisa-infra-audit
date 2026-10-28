# W-17 (상) 하드디스크 기본 공유 제거
# 판단 기준(가이드 원문): 양호 = AutoShareServer 가 0이며 기본 공유가 존재하지 않는 경우
#                        취약 = AutoShareServer 가 1이거나 기본 공유가 존재하는 경우
# W-R2: 예전에는 Get-SmbShare 실패를 "기본 공유 없음"으로 보아 AutoShareServer=0 이면 GOOD 이었다. 공유 목록을
# 확인하지 못했으면 AutoShareServer 만으로 VULN 이 확정되는 경우를 빼고 ERROR. W-R16: CDXML cmdlet 시간 제한.

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
$auto = Test-RegistryValue -Path $path -Name "AutoShareServer"

$shareErr = $null
try {
    $defaultShares = @(Invoke-CimCmdletWithTimeout -Command Get-SmbShare | Where-Object { $_.Name -match '^[A-Za-z]\$$' -or $_.Name -eq 'ADMIN$' })
} catch {
    $defaultShares = @()
    $shareErr = $_.Exception.Message
}

$evidence = "AutoShareServer=$auto`n기본 공유: " + $(if ($shareErr) { "조회 실패($shareErr)" } else { ($defaultShares | ForEach-Object { $_.Name }) -join ", " })

if ($null -ne $auto -and "$auto" -eq "0" -and -not $shareErr -and $defaultShares.Count -eq 0) {
    return New-CheckResult -Code "W-17" -Status "GOOD" -Detail "AutoShareServer=0 이며 기본(관리용) 공유가 존재하지 않음" -Evidence $evidence
} elseif ($shareErr -and "$auto" -eq "0") {
    return New-CheckResult -Code "W-17" -Status "ERROR" -Detail "AutoShareServer=0 이나 공유 목록을 조회하지 못해 기본 공유 존재 여부를 확인할 수 없음: $shareErr" -Evidence $evidence
} else {
    # AutoShareServer 미설정($null)은 기본값(기본 공유 자동 생성)이라 취약 조건에 해당한다 - 기존 판정 유지
    return New-CheckResult -Code "W-17" -Status "VULN" -Detail "AutoShareServer 가 0이 아니거나 기본(관리용) 공유가 존재함" -Evidence $evidence
}
