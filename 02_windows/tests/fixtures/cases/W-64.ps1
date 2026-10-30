# W-64 케이스. 가이드: 양호 = Windows 방화벽 사용 / 취약 = 사용 안 함(프로필 하나라도 꺼져 있으면 취약)
@{
    FirewallRulesHard = $true   # 조치(Enable-FixFirewallSafely)가 원격 관리 규칙을 켜고 원복한다 - 규칙 차이도 실패로 본다
    # 방화벽을 켜고 끄면 OS 가 IKEEXT 시작 유형을 바꾼다(CI run 40979700732) - 함께 원복
    Resources = @(@{ Svc = 'IKEEXT' }, @{
            Save    = { @(Get-NetFirewallProfile | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Enabled = "$($_.Enabled)" } }) }
            Restore = { param($s) foreach ($p in @($s)) { Set-NetFirewallProfile -Name $p.Name -Enabled $(if ($p.Enabled -eq 'True') { 'True' } else { 'False' }) } }
        })
    States    = [ordered]@{
        'all-off'    = @{
            Set   = { Set-NetFirewallProfile -All -Enabled False }
            Check = { $e = Get-CaseFirewallEnabled; if ($e -notmatch '=True') { $true } else { $e } }
        }
        'public-off' = @{
            Set   = { Set-NetFirewallProfile -All -Enabled True; Set-NetFirewallProfile -Name Public -Enabled False }
            Check = { $e = Get-CaseFirewallEnabled; if ($e -match 'Public=False' -and $e -match 'Domain=True' -and $e -match 'Private=True') { $true } else { $e } }
        }
        'all-on'     = @{
            Set   = { Set-NetFirewallProfile -All -Enabled True }
            Check = { $e = Get-CaseFirewallEnabled; if ($e -notmatch '=False') { $true } else { $e } }
        }
    }
    Fix       = @{ From = 'all-off' }
}
