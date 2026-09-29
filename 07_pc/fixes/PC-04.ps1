# PC-04 (상) 공유 폴더 제거 [fix: auto]
# checks/PC-04.ps1: 취약 = 기본(관리용) 공유가 존재하거나, 일반 공유에 Everyone 권한이 있는 경우.
# AutoShareWks=0 설정(다음 재시작부터 적용) + 현재 활성 기본 공유 즉시 제거 + 일반 공유의
# Everyone 권한 제거. 기본 공유 제거는 02_windows/fixes/W-17.ps1 과 동일한 이유로 즉시 제거만
# 수행하고 원복 대상에는 포함하지 않는다.

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "AutoShareWks" -Value 0 -Type DWord
$details = @($Global:FixDetail)

try {
    $allShares = Get-SmbShare -ErrorAction Stop
} catch {
    $allShares = @()
}

$defaultShares = $allShares | Where-Object { $_.Name -match '^[A-Za-z]\$$' -or $_.Name -eq 'ADMIN$' }
foreach ($s in $defaultShares) {
    Remove-SmbShare -Name $s.Name -Force -ErrorAction SilentlyContinue
}
if ($defaultShares) { $details += "활성 기본 공유 즉시 제거: $(($defaultShares | ForEach-Object { $_.Name }) -join ', ')" }

$generalShares = $allShares | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'print$' }
$everyoneApplied = @()
foreach ($s in $generalShares) {
    $access = Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue
    if (-not ($access | Where-Object { $_.AccountName -match "Everyone" })) { continue }
    Revoke-FixShareEveryone -ShareName $s.Name
    if ($Global:FixStatus -eq "APPLIED") { $everyoneApplied += $s.Name }
}
if ($everyoneApplied) { $details += "일반 공유에서 Everyone 권한 제거: $($everyoneApplied -join ', ')" }

$Global:FixStatus = "APPLIED"
$Global:FixDetail = $details -join "; "
