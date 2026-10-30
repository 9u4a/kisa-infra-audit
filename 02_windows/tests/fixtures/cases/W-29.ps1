# W-29 케이스. 가이드: 양호 = SNMP 미사용 또는 Community String 을 설정해 사용 / 취약 = 불필요하게 사용(커뮤니티 미설정)
@{
    Resources = @(@{ Save = { Save-CaseRegKey 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters' }; Restore = { param($o) Restore-CaseRegKey $o } })
    States    = [ordered]@{
        'snmp-stopped'      = @{ Svc = @{ SNMP = 'Stopped' } }
        'snmp-no-community' = @{
            Svc   = @{ SNMP = 'Running' }
            Set   = { $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities'; if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; foreach ($n in (Get-Item $k).GetValueNames()) { if ($n) { Remove-ItemProperty -Path $k -Name $n } } }
            Check = { $n = @((Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities').GetValueNames() | Where-Object { $_ }); if ($n.Count -eq 0) { $true } else { "communities=$($n.Count)" } }
        }
        'snmp-community'    = @{
            Svc   = @{ SNMP = 'Running' }
            Set   = { $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities'; if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; New-ItemProperty -Path $k -Name 'kisaCase7Rq2' -PropertyType DWord -Value 4 -Force | Out-Null }
            Check = { $n = @((Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities').GetValueNames() | Where-Object { $_ }); if ($n -contains 'kisaCase7Rq2') { $true } else { "communities=$($n -join ',')" } }
        }
    }
    Fix       = @{ From = 'snmp-no-community' }
}
