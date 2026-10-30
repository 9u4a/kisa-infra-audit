# W-33 케이스. 가이드: 양호 = HTTP/FTP/SMTP 접속 시 배너가 보이지 않음 / 취약 = 보임.
# HTTP 는 실제 응답의 Server 헤더로 판정, FTP/SMTP 는 원격 접속 없이 배너를 볼 수 없어 구동 중이면 MANUAL(check 설계).
@{
    Resources = @(@{ Svc = 'WAS' }, @{
            Save    = { (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name removeServerHeader).Value }
            Restore = { param($v) Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name removeServerHeader -Value ([bool]$v) }
        })
    States    = [ordered]@{
        'server-header'   = @{
            Svc   = @{ W3SVC = 'Running'; FTPSVC = 'Stopped'; SMTPSVC = 'Stopped' }
            Set   = { Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name removeServerHeader -Value $false }
            Check = { $v = (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name removeServerHeader).Value; if ("$v" -eq 'False') { $true } else { "removeServerHeader=$v" } }
        }
        'header-removed'  = @{
            Svc   = @{ W3SVC = 'Running'; FTPSVC = 'Stopped'; SMTPSVC = 'Stopped' }
            Set   = { Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name removeServerHeader -Value $true }
            Check = { $v = (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name removeServerHeader).Value; if ("$v" -eq 'True') { $true } else { "removeServerHeader=$v" } }
        }
        'no-services'     = @{ Svc = @{ W3SVC = 'Stopped'; FTPSVC = 'Stopped'; SMTPSVC = 'Stopped' } }
        'ftp-only'        = @{ Svc = @{ W3SVC = 'Stopped'; FTPSVC = 'Running'; SMTPSVC = 'Stopped' } }
    }
    Fix       = @{ From = 'server-header' }
}
