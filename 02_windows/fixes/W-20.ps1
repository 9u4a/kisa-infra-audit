# W-20 (상) NetBIOS 바인딩 서비스 구동 점검 [fix: confirm]
# checks/W-20.ps1: 양호 = 활성 어댑터 전부 TcpipNetbiosOptions=2(사용 안 함).
# 이 값은 WMI 로 조회하지만 실제로는 어댑터별 레지스트리
# HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_<SettingID>\NetbiosOptions
# 에 저장되므로, 각 인터페이스 GUID 별로 Set-FixRegistryValue 를 반복 적용해 백업/원복이
# 가능하게 한다.
# F-W20(1.4.0): 예전에는 Tcpip\Parameters\Interfaces\<GUID> 에 썼다 - NetBIOS 설정이 아닌 엉뚱한 위치라 재검증이 계속 VULN
# 이었다(confirm 등급이라 fix_safety 의 -Yes 적용에서는 실행되지 않아 드러나지 않음, 양방향 케이스의 조치 검증으로 확인).

try {
    $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction Stop
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "네트워크 어댑터 구성 조회 실패: $($_.Exception.Message)"
    $Global:FixEvidence = ""
    return
}

if (-not $adapters) {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "IP가 활성화된 네트워크 어댑터가 없음"
    $Global:FixEvidence = ""
    return
}

$applied = @()
foreach ($a in $adapters) {
    if (-not $a.SettingID) { continue }
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_$($a.SettingID)"
    if (-not (Test-Path $path)) { continue }
    Set-FixRegistryValue -Path $path -Name "NetbiosOptions" -Value 2 -Type DWord
    $applied += $a.SettingID
}

if ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "인터페이스 $($applied.Count)개의 NetbiosOptions 를 2(사용 안 함)로 설정함"
} else {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "설정 가능한 인터페이스 레지스트리 경로를 찾지 못함"
}
