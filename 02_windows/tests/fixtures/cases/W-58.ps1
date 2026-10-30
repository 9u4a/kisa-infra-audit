# W-58 케이스. 가이드: 양호 = 홈 디렉터리에 Everyone 권한 없음(All Users, Default User 제외) / 취약 = 있음.
# C:\Users 아래 시험용 홈 디렉터리(상속 끊고 Administrators·SYSTEM 만)를 만들고 Everyone 을 더하거나 뺀다.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) Remove-Item -LiteralPath (Join-Path $env:SystemDrive 'Users\kisa_case_home') -Recurse -Force -ErrorAction SilentlyContinue } })
    States    = [ordered]@{
        'home-everyone' = @{
            Set   = {
                $d = Join-Path $env:SystemDrive 'Users\kisa_case_home'; New-Item -ItemType Directory -Force -Path $d | Out-Null
                Invoke-CaseIcacls @($d, '/inheritance:r', '/grant:r', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F', '*S-1-1-0:(OI)(CI)(RX)')
            }
            Check = { if (Test-CaseAclHasSid -Path (Join-Path $env:SystemDrive 'Users\kisa_case_home') -Sid 'S-1-1-0') { $true } else { "Everyone ACE 없음" } }
        }
        'home-private'  = @{
            Set   = {
                $d = Join-Path $env:SystemDrive 'Users\kisa_case_home'; New-Item -ItemType Directory -Force -Path $d | Out-Null
                Invoke-CaseIcacls @($d, '/inheritance:r', '/grant:r', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F')
            }
            Check = { if (-not (Test-CaseAclHasSid -Path (Join-Path $env:SystemDrive 'Users\kisa_case_home') -Sid 'S-1-1-0')) { $true } else { "Everyone ACE 있음" } }
        }
    }
    Fix       = @{ From = 'home-everyone' }
}
