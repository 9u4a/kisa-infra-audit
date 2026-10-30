# W-20 케이스. 가이드: 양호 = TCP/IP 와 NetBIOS 바인딩 제거 / 취약 = 제거되지 않음.
# 어댑터별 NetBIOS 설정(WMI SetTcpipNetbios: 1=사용, 2=사용 안 함)으로 만든다.
@{
    Resources = @(@{
            Save    = { @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object { [PSCustomObject]@{ Index = $_.Index; Opt = $_.TcpipNetbiosOptions } }) }
            Restore = {
                param($s)
                foreach ($a in @($s)) {
                    $w = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "Index=$($a.Index)"
                    if ($w.TcpipNetbiosOptions -ne $a.Opt) { [void]($w | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]$a.Opt }) }
                }
            }
        })
    States    = [ordered]@{
        'netbios-enabled'  = @{
            Set   = { Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object { [void]($_ | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]1 }) } }
            Check = { $o = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object { $_.TcpipNetbiosOptions }); if ($o.Count -gt 0 -and @($o | Where-Object { $_ -ne 1 }).Count -eq 0) { $true } else { "TcpipNetbiosOptions=$($o -join ',')" } }
        }
        'netbios-disabled' = @{
            Set   = { Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object { [void]($_ | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]2 }) } }
            Check = { $o = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object { $_.TcpipNetbiosOptions }); if ($o.Count -gt 0 -and @($o | Where-Object { $_ -ne 2 }).Count -eq 0) { $true } else { "TcpipNetbiosOptions=$($o -join ',')" } }
        }
    }
    Fix       = @{ From = 'netbios-enabled' }
}
