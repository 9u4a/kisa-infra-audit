# W-30 케이스. 가이드: 양호 = SNMP 미사용 또는 Community String 이 public/private 아님 / 취약 = 사용하며 public/private
@{
    Resources = @(@{ Save = { Save-CaseRegKey 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters' }; Restore = { param($o) Restore-CaseRegKey $o } })
    States    = [ordered]@{
        'community-public' = @{
            Svc   = @{ SNMP = 'Running' }
            Set   = { $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities'; if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; foreach ($n in (Get-Item $k).GetValueNames()) { if ($n) { Remove-ItemProperty -Path $k -Name $n } }; New-ItemProperty -Path $k -Name 'public' -PropertyType DWord -Value 4 -Force | Out-Null }
            Check = { $n = @((Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities').GetValueNames() | Where-Object { $_ }); if (($n -join ',') -eq 'public') { $true } else { "communities=$($n -join ',')" } }
        }
        'community-strong' = @{
            Svc   = @{ SNMP = 'Running' }
            Set   = { $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities'; if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; foreach ($n in (Get-Item $k).GetValueNames()) { if ($n) { Remove-ItemProperty -Path $k -Name $n } }; New-ItemProperty -Path $k -Name 'kisaCase7Rq2' -PropertyType DWord -Value 4 -Force | Out-Null }
            Check = { $n = @((Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities').GetValueNames() | Where-Object { $_ }); if (($n -join ',') -eq 'kisaCase7Rq2') { $true } else { "communities=$($n -join ',')" } }
        }
        'snmp-stopped'     = @{ Svc = @{ SNMP = 'Stopped' } }
    }
    Fix       = @{ From = 'community-public' }
}
