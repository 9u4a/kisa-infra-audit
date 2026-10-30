# W-21 케이스. 가이드: 양호 = FTP 미사용 또는 Secure FTP(FTPS) 사용 / 취약 = 암호화되지 않는 FTP 사용.
# ftps-required: 모든 FTP 사이트가 제어·데이터 채널 모두 SSL 필수(SslRequire)면 양호(F-W21, 이전에는 FTP 구동만으로 VULN).
# ftps-control-only: 데이터 채널은 평문 허용 - 취약.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) Remove-CaseFtpSites } })
    States    = [ordered]@{
        # New-WebFtpSite 로 만든 사이트의 기본 SSL 정책은 SslRequire(CI run 41009844085 실측) - 평문 허용(SslAllow)을 명시한다
        'ftp-plain-running' = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = {
                New-CaseFtpSite | Out-Null
                $f = "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/ssl"
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name controlChannelPolicy -Value 'SslAllow'
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name dataChannelPolicy -Value 'SslAllow'
            }
            Check = {
                $f = "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/ssl"
                $c = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name controlChannelPolicy
                $d = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name dataChannelPolicy
                if ("$c" -eq 'SslAllow' -and "$d" -eq 'SslAllow') { $true } else { "control=$c data=$d" }
            }
        }
        'ftps-required'     = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = {
                New-CaseFtpSite | Out-Null
                $f = "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/ssl"
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name controlChannelPolicy -Value 'SslRequire'
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name dataChannelPolicy -Value 'SslRequire'
            }
            Check = {
                $f = "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/ssl"
                $c = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name controlChannelPolicy
                $d = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name dataChannelPolicy
                if ("$c" -eq 'SslRequire' -and "$d" -eq 'SslRequire') { $true } else { "control=$c data=$d" }
            }
        }
        'ftps-control-only' = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = {
                New-CaseFtpSite | Out-Null
                $f = "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/ssl"
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name controlChannelPolicy -Value 'SslRequire'
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name dataChannelPolicy -Value 'SslAllow'
            }
            Check = {
                $f = "system.applicationHost/sites/site[@name='kisa_case_ftp']/ftpServer/security/ssl"
                $c = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name controlChannelPolicy
                $d = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $f -Name dataChannelPolicy
                if ("$c" -eq 'SslRequire' -and "$d" -eq 'SslAllow') { $true } else { "control=$c data=$d" }
            }
        }
        'ftp-stopped'       = @{ Svc = @{ FTPSVC = 'Stopped' } }
    }
    Fix       = @{ From = 'ftp-plain-running' }
}
