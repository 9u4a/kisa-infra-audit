# PC-04 케이스. 가이드: 양호 = 불필요한 공유 없음 또는 공유에 접근 권한 설정 / 취약 = 불필요한 공유(기본 관리 공유 포함) 존재 또는 권한 없이 공유.
# 기본 공유 없는 상태는 AutoShareServer/AutoShareWks=0 후 Server 서비스 재시작으로 만든다(실행 중 삭제는 이 러너에서 미지원).
# 조치는 즉시 지운 기본 공유를 되살리지 못한다(Register-FixNoRollback) - 원복 후에도 공유가 없어 GOOD, 공유 차이는 참고. 케이스 원복이 Server 서비스 재시작으로 되살린다.
@{
    Resources = @(@{
            Save    = { Get-CaseDefaultShares }
            Restore = {
                param($names)
                if (Get-SmbShare -Name 'kisa_case04' -ErrorAction SilentlyContinue) { Remove-SmbShare -Name 'kisa_case04' -Force }
                Remove-Item -Recurse -Force (Join-Path $env:SystemDrive 'kisa_case\share04') -ErrorAction SilentlyContinue
                $cur = Get-CaseDefaultShares; if (@(@($names) | Where-Object { $_ -and $cur -notcontains $_ }).Count -gt 0) { Restart-CaseLanman }
            }
        }, 
        # 조치·케이스가 Server 서비스를 재시작하면 Parameters\Guid 가 새로 써진다 - 항목 시작 값으로(위 재시작 원복보다 먼저 실행)
        @{ Save = { Get-CaseReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'Guid' }; Restore = { param($g) if ($null -ne $g) { Set-CaseReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'Guid' ([byte[]]$g) 'Binary' } } })
    States    = [ordered]@{
        'default-shares'   = @{ Check = { $s = Get-CaseDefaultShares; if ($s -contains 'ADMIN$') { $true } else { "기본 공유: $($s -join ',')" } } }
        'no-shares'        = @{
            Reg   = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareServer'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareWks'; V = 0 })
            Set   = { Restart-CaseLanman -NoWait }
            Check = { $s = Get-CaseDefaultShares; if ($s.Count -eq 0) { $true } else { "남은 기본 공유: $($s -join ',')" } }
        }
        'everyone-share'   = @{
            Reg   = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareServer'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareWks'; V = 0 })
            Set   = {
                Restart-CaseLanman -NoWait
                $dir = Join-Path $env:SystemDrive 'kisa_case\share04'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $everyone = (New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')).Translate([System.Security.Principal.NTAccount]).Value
                New-SmbShare -Name 'kisa_case04' -Path $dir -FullAccess $everyone | Out-Null
            }
            Check = { $a = @(Get-SmbShareAccess -Name 'kisa_case04' | Where-Object { $_.AccountName -eq 'Everyone' }); if ($a.Count -gt 0 -and (Get-CaseDefaultShares).Count -eq 0) { $true } else { "everyone=$($a.Count)" } }
        }
        'restricted-share' = @{
            Reg   = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareServer'; V = 0 }, @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareWks'; V = 0 })
            Set   = {
                Restart-CaseLanman -NoWait
                $dir = Join-Path $env:SystemDrive 'kisa_case\share04'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $admins = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value
                New-SmbShare -Name 'kisa_case04' -Path $dir -FullAccess $admins | Out-Null
            }
            Check = { $s = Get-SmbShare -Name 'kisa_case04' -ErrorAction SilentlyContinue; $a = @(Get-SmbShareAccess -Name 'kisa_case04' | Where-Object { $_.AccountName -eq 'Everyone' }); if ($s -and $a.Count -eq 0 -and (Get-CaseDefaultShares).Count -eq 0) { $true } else { "share=$([bool]$s) everyone=$($a.Count)" } }
        }
    }
    Fix       = @{ From = 'default-shares'; AfterRollback = 'GOOD'; SoftAreas = @('shares'); SoftLines = @('\\LanmanServer\\Parameters\|Guid\|') }
}