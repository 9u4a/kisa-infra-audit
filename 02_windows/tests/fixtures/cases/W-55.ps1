# W-55 케이스. 가이드: 양호 = "사용자가 프린터 드라이버를 설치할 수 없게 함" 사용 / 취약 = 사용 안 함
@{
    States = [ordered]@{
        'users-can-install' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers'; N = 'AddPrinterDrivers'; V = 0 }) }
        'restricted'        = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers'; N = 'AddPrinterDrivers'; V = 1 }) }
    }
    Fix    = @{ From = 'users-can-install' }
}