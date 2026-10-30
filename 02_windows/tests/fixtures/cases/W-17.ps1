# W-17 케이스. 가이드: 양호 = AutoShareServer 가 0 이며 기본 공유가 존재하지 않음 / 취약 = AutoShareServer 가 1(미설정 = 기본값 생성)
# 이거나 기본 공유가 존재. 조치는 즉시 지운 기본 공유를 되살리지 못한다(Register-FixNoRollback) - 원복 후에도 AutoShareServer 가
# 원래(미설정)로 돌아오므로 판정은 VULN, 공유 목록 차이는 원복 불가 범위로 참고 처리. 케이스 원복이 Server 서비스 재시작으로 되살린다.
@{
    Resources = @(@{
            Save    = { Get-CaseDefaultShares }
            Restore = { param($names) $cur = Get-CaseDefaultShares; if (@(@($names) | Where-Object { $_ -and $cur -notcontains $_ }).Count -gt 0) { Restart-CaseLanman } }
        }, 
        # 조치·케이스가 Server 서비스를 재시작하면 Parameters\Guid 가 새로 써진다 - 항목 시작 값으로(위 재시작 원복보다 먼저 실행)
        @{ Save = { Get-CaseReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'Guid' }; Restore = { param($g) if ($null -ne $g) { Set-CaseReg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'Guid' ([byte[]]$g) 'Binary' } } })
    States    = [ordered]@{
        'default-shares'      = @{
            Reg   = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareServer'; V = $null })
            Check = { $s = Get-CaseDefaultShares; if ($s -contains 'ADMIN$') { $true } else { "기본 공유: $($s -join ',')" } }
        }
        'auto-0-shares-exist' = @{
            Reg   = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareServer'; V = 0 })
            Check = { $s = Get-CaseDefaultShares; if ($s -contains 'ADMIN$') { $true } else { "기본 공유: $($s -join ',')" } }
        }
        'no-default-shares'   = @{
            # 실행 중 기본 공유 삭제(Remove-SmbShare)는 이 러너(Server 2025)에서 "The request is not supported" - 레지스트리 0 후 Server 서비스 재시작
            Reg   = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N = 'AutoShareServer'; V = 0 })
            Set   = { Restart-CaseLanman -NoWait }
            Check = { $s = Get-CaseDefaultShares; if ($s.Count -eq 0) { $true } else { "남은 기본 공유: $($s -join ',')" } }
        }
    }
    Fix       = @{ From = 'default-shares'; AfterRollback = 'VULN'; SoftAreas = @('shares'); SoftLines = @('\\LanmanServer\\Parameters\|Guid\|') }
}
