# PC-04 (상) 공유 폴더 제거 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 원복: 일부 — 레지스트리는 되돌리지만 중지한 기본 공유는 Server 서비스 재시작/재부팅 후에야 다시 생김(실행 중 삭제가 거부되면 조치가 Server 서비스를 재시작 - SMB 연결 끊김)
# checks/PC-04.ps1: 취약 = 기본(관리용) 공유가 존재하거나, 일반 공유에 Everyone 권한이 있는 경우.
# AutoShareWks=0 설정(다음 재시작부터 적용) + 현재 활성 기본 공유 즉시 제거 + 일반 공유의
# Everyone 권한 제거. 기본 공유 제거는 02_windows/fixes/W-17.ps1 과 동일한 이유로 즉시 제거만
# 수행하고 원복 대상에는 포함하지 않는다.

# F-W17(1.4.0): 자동 기본 공유 레지스트리는 클라이언트 OS 가 AutoShareWks, 서버 OS 가 AutoShareServer 를 읽는다 - 아래에서 실행 중
# 공유 삭제가 거부되면 Server 서비스를 재시작하므로 그 OS 가 읽는 값을 써야 재시작 후 다시 생기지 않는다.
$isWorkstation = ((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).ProductType -eq 1)
$autoName = if ($isWorkstation) { "AutoShareWks" } else { "AutoShareServer" }
Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name $autoName -Value 0 -Type DWord
$details = @($Global:FixDetail)
$shareError = ""

# 원복 경로가 없는 자원 - 원복 시 "원복 불가"로 정직하게 보고되도록 변경 직전에 표시(lib/Common.psm1)
Register-FixNoRollback -Reason "즉시 삭제한 기본 공유(ADMIN$/C$ 등) - 레지스트리는 원복되지만 공유는 Server 서비스 재시작/재부팅 후에야 다시 생김"
try {
    $allShares = Get-SmbShare -ErrorAction Stop
} catch {
    $allShares = @()
}

# 삭제 실패를 숨기지 않는다(F-W17) - 거부되면 Server 서비스 재시작으로 중지, 그래도 남으면 ERROR
try {
    $r = Remove-FixDefaultShares
    if ($r.Removed.Count -gt 0) { $details += "기본 공유 중지: $($r.Removed -join ', ')$(if ($r.Restarted) { ' (실행 중 삭제가 거부되어 Server 서비스 재시작)' })" }
    if ($r.Remaining.Count -gt 0) { $shareError = "기본 공유를 중지하지 못함: $($r.Remaining -join ', ')" }
} catch { $shareError = "기본 공유 중지 실패: $($_.Exception.Message)" }

$generalShares = $allShares | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'print$' }
$everyoneApplied = @()
foreach ($s in $generalShares) {
    $access = Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue
    if (-not ($access | Where-Object { $_.AccountName -match "Everyone" })) { continue }
    Revoke-FixShareEveryone -ShareName $s.Name
    if ($Global:FixStatus -eq "APPLIED") { $everyoneApplied += $s.Name }
}
if ($everyoneApplied) { $details += "일반 공유에서 Everyone 권한 제거: $($everyoneApplied -join ', ')" }

if ($shareError) { $details += $shareError }
$Global:FixStatus = if ($shareError) { "ERROR" } else { "APPLIED" }
$Global:FixDetail = $details -join "; "
