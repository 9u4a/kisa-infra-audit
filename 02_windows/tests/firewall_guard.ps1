# 02_windows/tests/firewall_guard.ps1 — Enable-FixFirewallSafely(W-64/PC-15/MSSQL D-10 공용) 안전장치 테스트.
# GitHub Actions windows-latest(휘발성 VM)에서만 실행한다 - 방화벽 프로필과 규칙을 실제로 바꾼다.
#   A) 필요한 포트의 허용 규칙이 없으면 켜지 않고(ERROR) 원격 관리 규칙도 원래대로 둔다
#   B) 허용 규칙을 만들면 켠다(APPLIED)
#   C) Restore-FixItem 이 프로필 상태와 새로 켠 원격 관리 규칙을 되돌린다
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Import-Module (Join-Path $Repo "lib\Common.psm1") -Force

$port = 59999                       # 어떤 기본 규칙도 열지 않는 포트 - "허용 규칙 없음" 상황을 확정적으로 만든다
$rdpGroup = '@FirewallAPI.dll,-28752'
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Get-NetFirewallRule -Group $rdpGroup -ErrorAction SilentlyContinue | Disable-NetFirewallRule
Remove-NetFirewallRule -Name "kisa-test-$port" -ErrorAction SilentlyContinue
Set-NetFirewallProfile -All -Enabled False

function Get-State {
    [PSCustomObject]@{
        On = @(Get-NetFirewallProfile | Where-Object { "$($_.Enabled)" -eq "True" }).Count
        RdpRulesOn = @(Get-NetFirewallRule -Group $rdpGroup -ErrorAction SilentlyContinue | Where-Object { "$($_.Enabled)" -eq "True" }).Count
    }
}
$fail = @()
$rdpRuleCount = @(Get-NetFirewallRule -Group $rdpGroup -ErrorAction SilentlyContinue).Count
Write-Host "원격 데스크톱 규칙 그룹(리소스 ID) 규칙 수: $rdpRuleCount"
if ($rdpRuleCount -eq 0) { $fail += "원격 데스크톱 규칙 그룹을 리소스 ID 로 찾지 못함" }

# A) 허용 규칙 없음
$Global:FixBackupDir = Join-Path $env:TEMP "fwguard_a"; Remove-Item -Recurse -Force $Global:FixBackupDir -ErrorAction SilentlyContinue
$Global:FixCode = "W-64"; $Global:FixRollbackFailures = @()
Enable-FixFirewallSafely -RequiredPorts @($port)
$s = Get-State
Write-Host "A) $($Global:FixStatus): $($Global:FixDetail) / 켜진 프로필=$($s.On) RDP규칙=$($s.RdpRulesOn)"
if ($Global:FixStatus -ne "ERROR" -or $s.On -ne 0 -or $s.RdpRulesOn -ne 0) { $fail += "A) 허용 규칙이 없는데 방화벽/규칙 상태가 바뀜" }

# B) 허용 규칙 있음
New-NetFirewallRule -Name "kisa-test-$port" -DisplayName "kisa test $port" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
$Global:FixBackupDir = Join-Path $env:TEMP "fwguard_b"; Remove-Item -Recurse -Force $Global:FixBackupDir -ErrorAction SilentlyContinue
Enable-FixFirewallSafely -RequiredPorts @($port)
$s = Get-State
Write-Host "B) $($Global:FixStatus): $($Global:FixDetail) / 켜진 프로필=$($s.On) RDP규칙=$($s.RdpRulesOn)"
if ($Global:FixStatus -ne "APPLIED" -or $s.On -ne 3 -or $s.RdpRulesOn -eq 0) { $fail += "B) 허용 규칙이 있는데 켜지지 않음(또는 RDP 규칙 미활성)" }

# C) 원복
$Global:FixRollbackFailures = @()
Restore-FixItem -Code "W-64"
$s = Get-State
Write-Host "C) 원복 후 켜진 프로필=$($s.On) RDP규칙=$($s.RdpRulesOn) 원복실패=$(@($Global:FixRollbackFailures).Count)"
if ($s.On -ne 0 -or $s.RdpRulesOn -ne 0 -or @($Global:FixRollbackFailures).Count -gt 0) { $fail += "C) 원복 후 프로필/규칙이 조치 전과 다름: $($Global:FixRollbackFailures -join ' / ')" }

if ($fail.Count -gt 0) { Write-Host "FAIL: firewall-guard"; $fail | ForEach-Object { Write-Host "  - $_" }; exit 1 }
Write-Host "PASS: firewall-guard"
