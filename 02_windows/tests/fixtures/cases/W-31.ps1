# W-31 케이스. 가이드: 양호 = SNMP 미사용 또는 특정 호스트로부터만 패킷 수신 / 취약 = 모든 호스트로부터 수신
@{
    Resources = @(@{ Save = { Save-CaseRegKey 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters' }; Restore = { param($o) Restore-CaseRegKey $o } })
    States    = [ordered]@{
        'any-host'       = @{
            Svc   = @{ SNMP = 'Running' }
            Set   = { $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers'; if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; foreach ($n in (Get-Item $k).GetValueNames()) { if ($n) { Remove-ItemProperty -Path $k -Name $n } } }
            Check = { $n = @((Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers').GetValueNames() | Where-Object { $_ }); if ($n.Count -eq 0) { $true } else { "managers=$($n.Count)" } }
        }
        'localhost-only' = @{
            Svc   = @{ SNMP = 'Running' }
            Set   = { $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers'; if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; New-ItemProperty -Path $k -Name '1' -PropertyType String -Value 'localhost' -Force | Out-Null }
            Check = { $v = (Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\PermittedManagers').GetValue('1'); if ($v -eq 'localhost') { $true } else { "1=$v" } }
        }
        'snmp-stopped'   = @{ Svc = @{ SNMP = 'Stopped' } }
    }
    Fix       = @{ From = 'any-host' }
}
