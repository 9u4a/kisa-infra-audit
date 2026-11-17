# W-32 케이스. 가이드: 양호 = DNS 미사용 또는 동적 업데이트 "없음" / 취약 = 사용하며 동적 업데이트 설정. 조치는 manual.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) if (Test-CaseDnsZone) { Remove-DnsServerZone -Name 'kisa-case.test' -Force } } })
    States    = [ordered]@{
        'dns-stopped'       = @{ Svc = @{ DNS = 'Stopped' } }
        'dynamic-nonsecure' = @{
            Svc   = @{ DNS = 'Running' }
            Set   = {
                New-CaseDnsZone
                Set-DnsServerPrimaryZone -Name 'kisa-case.test' -DynamicUpdate NonsecureAndSecure
            }
            Check = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.AllowUpdate -eq 1) { $true } else { "AllowUpdate=$($z.AllowUpdate)" } }
        }
        'dynamic-none'      = @{
            Svc   = @{ DNS = 'Running' }
            Set   = {
                New-CaseDnsZone
                Set-DnsServerPrimaryZone -Name 'kisa-case.test' -DynamicUpdate None
            }
            Check = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.AllowUpdate -eq 0) { $true } else { "AllowUpdate=$($z.AllowUpdate)" } }
        }
    }
    # 1.7.0 값 지정 조치: 정책 값(W-32.zones)에 적은 영역만 동적 업데이트 없음(0) → 원복 시 원래 값(1)으로
    Fix       = @{
        From = 'dynamic-nonsecure'; Expect = 'GOOD'; Params = @{ zones = @('kisa-case.test') }
        Verify = { $z = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Zone -Filter "Name='kisa-case.test'"; if ($z -and $z.AllowUpdate -eq 0) { $true } else { "AllowUpdate=$($z.AllowUpdate)" } }
    }
    FixReject = @{ From = 'dynamic-nonsecure'; Params = @{ zones = @('kisa-case.test', 'no-such-zone.test') } }
}
