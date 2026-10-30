# W-23 케이스. 가이드: 양호 = 공유 서비스 미사용 또는 익명 인증 사용 안 함 / 취약 = 익명 인증 사용.
# FTP 구동 시 사이트별 FTP 익명 인증, FTP 미사용 시 SMB Null Session 제한(LanmanServer, 예전 위치 Lsa)으로 판정한다.
@{
    Resources = @(@{
            Save    = { (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/ftpServer/security/authentication/anonymousAuthentication' -Name enabled).Value }
            Restore = {
                param($v)
                Remove-CaseFtpSites
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/ftpServer/security/authentication/anonymousAuthentication' -Name enabled -Value ([bool]$v)
            }
        })
    States    = [ordered]@{
        'smb-null-allowed'    = @{ Svc = @{ FTPSVC = 'Stopped' }; Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'RestrictNullSessAccess'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictNullSessAccess'; V = $null }) }
        'smb-null-restricted' = @{ Svc = @{ FTPSVC = 'Stopped' }; Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'RestrictNullSessAccess'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictNullSessAccess'; V = $null }) }
        'smb-lsa-legacy-0'    = @{ Svc = @{ FTPSVC = 'Stopped' }; Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'RestrictNullSessAccess'; V = 1 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictNullSessAccess'; V = 0 }) }
        'ftp-anonymous'       = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = { New-CaseFtpSite | Out-Null; Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/authentication/anonymousAuthentication" -Name enabled -Value $true }
            Check = { $v = (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/authentication/anonymousAuthentication" -Name enabled).Value; if ("$v" -eq 'True') { $true } else { "enabled=$v" } }
        }
        'ftp-no-anonymous'    = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = { New-CaseFtpSite | Out-Null; Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/authentication/anonymousAuthentication" -Name enabled -Value $false }
            Check = { $v = (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/authentication/anonymousAuthentication" -Name enabled).Value; if ("$v" -eq 'False') { $true } else { "enabled=$v" } }
        }
    }
    Fix       = @{ From = 'smb-null-allowed' }
}
