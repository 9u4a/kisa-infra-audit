# W-54 케이스. 가이드: 양호 = SynAttackProtect>=1, EnableDeadGWDetect=0, KeepAliveTime=300000, NoNameReleaseOnDemand=1 / 취약 = 설정되지 않음
@{
    States = [ordered]@{
        'unset'   = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'SynAttackProtect'; V = $null }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'EnableDeadGWDetect'; V = $null }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'KeepAliveTime'; V = $null }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'NoNameReleaseOnDemand'; V = $null }) }
        'partial' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'SynAttackProtect'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'EnableDeadGWDetect'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'KeepAliveTime'; V = 7200000 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'NoNameReleaseOnDemand'; V = 1 }) }
        'all-set' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'SynAttackProtect'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'EnableDeadGWDetect'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'KeepAliveTime'; V = 300000 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; N = 'NoNameReleaseOnDemand'; V = 1 }) }
    }
    Fix    = @{ From = 'unset' }
}