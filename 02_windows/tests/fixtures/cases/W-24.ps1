# W-24 케이스. 가이드: 양호 = 특정 IP 에서만 FTP 접속하도록 접근 제어 / 취약 = 접근 제어 미적용. 조치는 manual(허용 IP 를 정할 수 없음)
# A9: 가이드 비고 "마스터 속성과 모든 사이트에 적용" - 마스터만 막고 사이트 <location> 에서 allowUnlisted=true 로 연 상태가 예전 거짓 GOOD
@{
    Resources = @(@{
            Save    = { $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'; [PSCustomObject]@{ Allow = "$($s.allowUnlisted)" -ne 'False'; Ips = @($s.Collection | ForEach-Object { $_.ipAddress }) } }
            Restore = {
                param($o)
                # 사이트 단위 <location path="kisa_case_ftp"> 설정은 사이트를 지워도 applicationHost.config 에 남을 수 있어 먼저 지운다
                # 사이트가 없는 상태(ftp-stopped 등)에서는 "Unrecognized configuration path" 종료 오류가 나므로(-ErrorAction 무시됨)
                # 사이트가 있을 때만 지운다 - 사이트가 없으면 앞선 상태의 원복에서 이미 지워졌다
                if (Get-Website -Name 'kisa_case_ftp' -ErrorAction SilentlyContinue) {
                    try { Clear-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'kisa_case_ftp' -Filter '/system.ftpServer/security/ipSecurity' -ErrorAction Stop } catch { Write-Verbose "location 정리 생략: $_" }
                }
                Remove-CaseFtpSites
                foreach ($ip in @((Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\').Collection | ForEach-Object { $_.ipAddress })) {
                    if (@($o.Ips) -notcontains $ip) { Remove-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name '.' -AtElement @{ ipAddress = $ip } }
                }
                Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $o.Allow
            }
        })
    States    = [ordered]@{
        'no-ip-restriction' = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = { New-CaseFtpSite | Out-Null; Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $true }
            Check = { $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'; if ("$($s.allowUnlisted)" -ne 'False') { $true } else { "allowUnlisted=$($s.allowUnlisted)" } }
        }
        'ip-restricted'     = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = {
                New-CaseFtpSite | Out-Null
                Add-WebConfiguration -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Value @{ ipAddress = '127.0.0.1'; allowed = 'true' }
                Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $false
            }
            Check = { $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'; if ("$($s.allowUnlisted)" -eq 'False' -and @($s.Collection).Count -gt 0) { $true } else { "allowUnlisted=$($s.allowUnlisted) rules=$(@($s.Collection).Count)" } }
        }
        'site-override-open' = @{
            Svc   = @{ FTPSVC = 'Running' }
            Set   = {
                New-CaseFtpSite | Out-Null
                Add-WebConfiguration -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Value @{ ipAddress = '127.0.0.1'; allowed = 'true' }
                Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $false
                Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'kisa_case_ftp' -Filter '/system.ftpServer/security/ipSecurity' -Name allowUnlisted -Value $true
            }
            Check = {
                $m = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'
                $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'kisa_case_ftp'
                if ("$($m.allowUnlisted)" -eq 'False' -and "$($s.allowUnlisted)" -eq 'True') { $true } else { "master=$($m.allowUnlisted) site=$($s.allowUnlisted)" }
            }
        }
        'ftp-stopped'       = @{ Svc = @{ FTPSVC = 'Stopped' } }
    }
    # 1.7.0 값 지정 조치: 정책 값 W-24.allow 의 IP 를 마스터에 추가하고 마스터·사이트 모두 목록 외 거부 → 양호. 원복하면 추가한 IP 를 빼고
    # 사이트 location 의 allowUnlisted=true 로 돌아온다(마스터만 막고 사이트가 연 A9 상태 그대로)
    Fix       = @{
        From = 'site-override-open'; Expect = 'GOOD'; Params = @{ allow = @('10.20.30.40') }
        Verify = {
            $m = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'IIS:\'
            $s = Get-WebConfiguration -Filter '/system.ftpServer/security/ipSecurity' -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'kisa_case_ftp'
            $ips = @($m.Collection | ForEach-Object { $_.ipAddress })
            if ("$($m.allowUnlisted)" -eq 'False' -and "$($s.allowUnlisted)" -eq 'False' -and $ips -contains '10.20.30.40') { $true } else { "master=$($m.allowUnlisted) site=$($s.allowUnlisted) ips=$($ips -join ',')" }
        }
    }
    # 값 검증 거부: 0.0.0.0(전체 허용)이 섞이면 아무것도 바꾸지 않는다
    FixReject = @{ From = 'site-override-open'; Params = @{ allow = @('10.20.30.40', '0.0.0.0') } }
}
