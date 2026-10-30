# W-25 케이스. 가이드: 양호 = DNS 비활성화, 영역 전송 미허용, 또는 특정 서버로만 / 취약 = 셋 다 아님(모든 서버로 전송 허용).
# 조치는 영역 설정(WMI)을 되돌리지 못한다(Register-FixNoRollback) - 원복 후 판정은 조치 결과(GOOD) 그대로.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) if (Test-CaseDnsZone) { Remove-DnsServerZone -Name 'kisa-case.test' -Force } } })
    States    = [ordered]@{
        'dns-stopped'       = @{ Svc = @{ DNS = 'Stopped' } }
        'transfer-any'      = @{
            Svc   = @{ DNS = 'Running' }
            Set   = {
                if (-not (Test-CaseDnsZone)) { Add-DnsServerPrimaryZone -Name 'kisa-case.test' -ZoneFile 'kisa-case.test.dns' }
                Set-DnsServerPrimaryZone -Name 'kisa-case.test' -SecureSecondaries TransferAnyServer
            }
            Check = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.SecureSecondaries -eq 0) { $true } else { "SecureSecondaries=$($z.SecureSecondaries)" } }
        }
        'no-transfer'       = @{
            Svc   = @{ DNS = 'Running' }
            Set   = {
                if (-not (Test-CaseDnsZone)) { Add-DnsServerPrimaryZone -Name 'kisa-case.test' -ZoneFile 'kisa-case.test.dns' }
                Set-DnsServerPrimaryZone -Name 'kisa-case.test' -SecureSecondaries NoTransfer
            }
            Check = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.SecureSecondaries -eq 3) { $true } else { "SecureSecondaries=$($z.SecureSecondaries)" } }
        }
        'transfer-specific' = @{
            Svc   = @{ DNS = 'Running' }
            Set   = {
                if (-not (Test-CaseDnsZone)) { Add-DnsServerPrimaryZone -Name 'kisa-case.test' -ZoneFile 'kisa-case.test.dns' }
                Set-DnsServerPrimaryZone -Name 'kisa-case.test' -SecureSecondaries TransferToSecureServers -SecondaryServers '192.0.2.10'
            }
            Check = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.SecureSecondaries -eq 2) { $true } else { "SecureSecondaries=$($z.SecureSecondaries)" } }
        }
    }
    Fix       = @{ From = 'transfer-any'; AfterRollback = 'GOOD' }
}
