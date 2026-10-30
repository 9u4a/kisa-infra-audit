# PC-15 케이스. 가이드: 양호 = Windows 방화벽 사용 또는 기타 방화벽 사용 / 취약 = Windows 방화벽 미사용 및 기타 방화벽 미사용.
# 러너(Windows Server 2025)에서도 보안 센터(SecurityCenter2) FirewallProduct 조회가 되어(CI run 40981289087) 꺼짐 → VULN 으로 판정된다.
@{
    FirewallRulesHard = $true   # 조치(Enable-FixFirewallSafely)가 원격 관리 규칙을 켜고 원복한다 - 규칙 차이도 실패로 본다
    # 방화벽을 켜고 끄면 OS 가 IKEEXT 시작 유형을 바꾼다(CI run 40979700732) - 함께 원복
    Resources = @(@{ Svc = 'IKEEXT' }, @{
            Save    = { @(Get-NetFirewallProfile | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Enabled = "$($_.Enabled)" } }) }
            Restore = { param($s) foreach ($p in @($s)) { Set-NetFirewallProfile -Name $p.Name -Enabled $(if ($p.Enabled -eq 'True') { 'True' } else { 'False' }) } }
        })
    States    = [ordered]@{
        'firewall-off' = @{
            Set   = { Set-NetFirewallProfile -All -Enabled False }
            Check = { $e = Get-CaseFirewallEnabled; if ($e -notmatch '=True') { $true } else { $e } }
        }
        'firewall-on'                    = @{
            Set   = { Set-NetFirewallProfile -All -Enabled True }
            Check = { $e = Get-CaseFirewallEnabled; if ($e -notmatch '=False') { $true } else { $e } }
        }
    }
    Fix       = @{ From = 'firewall-off' }
}