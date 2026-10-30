# W-14 케이스. 가이드: 양호 = 관리자 외 원격 접속용 별도 계정을 Remote Desktop Users 에 등록 / 취약 = 별도 계정 없음.
# 조치는 manual(계정 생성은 자동화 대상 아님).
@{
    Resources = @(@{
            Save    = { @(Get-LocalGroupMember -SID 'S-1-5-32-555' | ForEach-Object { $_.SID.Value }) }
            Restore = {
                param($sids)
                $cur = @(Get-LocalGroupMember -SID 'S-1-5-32-555' | ForEach-Object { $_.SID.Value })
                foreach ($s in $cur) { if (@($sids) -notcontains $s) { Remove-LocalGroupMember -SID 'S-1-5-32-555' -Member $s } }
                foreach ($s in @($sids)) { if ($s -and $cur -notcontains $s) { Add-LocalGroupMember -SID 'S-1-5-32-555' -Member $s } }
                Remove-CaseLocalUser 'kisa_case_rdp'
            }
        })
    States    = [ordered]@{
        'no-rdp-users' = @{
            Set   = { foreach ($m in @(Get-LocalGroupMember -SID 'S-1-5-32-555')) { Remove-LocalGroupMember -SID 'S-1-5-32-555' -Member $m.SID.Value } }
            Check = { $n = @(Get-LocalGroupMember -SID 'S-1-5-32-555').Count; if ($n -eq 0) { $true } else { "members=$n" } }
        }
        'rdp-user'     = @{
            Set   = { New-CaseLocalUser 'kisa_case_rdp'; Add-LocalGroupMember -SID 'S-1-5-32-555' -Member 'kisa_case_rdp' }
            Check = { $m = @(Get-LocalGroupMember -SID 'S-1-5-32-555' | Where-Object { $_.Name -like '*\kisa_case_rdp' }); if ($m.Count -eq 1) { $true } else { "kisa_case_rdp 미등록" } }
        }
    }
}
