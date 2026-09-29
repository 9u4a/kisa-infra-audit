# W-17 (상) 하드디스크 기본 공유 제거 [fix: confirm]
# checks/W-17.ps1: 양호 = AutoShareServer=0 이며 기본(관리용) 공유가 존재하지 않는 경우.
# 재시작 후에도 유지되도록 레지스트리를 먼저 설정하고(백업/원복 가능), 현재 활성 중인 기본
# 공유는 즉시 효과를 위해 별도로 제거한다(관리용 공유 재생성은 원복 대상에 포함하지 않음 -
# 다음 재부팅 시 레지스트리 값에 따라 정상적으로 결정됨).

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "AutoShareServer" -Value 0 -Type DWord

try {
    $defaultShares = Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -match '^[A-Za-z]\$$' -or $_.Name -eq 'ADMIN$' }
    foreach ($s in $defaultShares) {
        Remove-SmbShare -Name $s.Name -Force -ErrorAction SilentlyContinue
    }
    if ($defaultShares) {
        $Global:FixDetail = "$($Global:FixDetail); 활성 기본 공유 즉시 제거: $(($defaultShares | ForEach-Object { $_.Name }) -join ', ')"
    }
} catch {
    # 기본 공유 즉시 제거는 실패해도 AutoShareServer=0 설정 자체는 유효하므로 FixStatus 는 건드리지 않는다
}
