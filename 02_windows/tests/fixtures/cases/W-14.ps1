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
        # 1.7.0 값 지정 조치: 원격 접속용 계정은 만들어 뒀지만 그룹에 등록하지 않은 상태(취약)
        'rdp-account-unregistered' = @{
            Set   = {
                foreach ($m in @(Get-LocalGroupMember -SID 'S-1-5-32-555')) { Remove-LocalGroupMember -SID 'S-1-5-32-555' -Member $m.SID.Value }
                New-CaseLocalUser 'kisa_case_rdp'
            }
            Check = { $n = @(Get-LocalGroupMember -SID 'S-1-5-32-555').Count; if ($n -eq 0 -and (Get-LocalUser 'kisa_case_rdp' -ErrorAction SilentlyContinue)) { $true } else { "members=$n" } }
        }
    }
    # 정책 값(W-14.members)의 계정만 Remote Desktop Users 에 등록 → 양호. 원복하면 이 조치가 추가한 구성원만 빠진다
    Fix       = @{
        From = 'rdp-account-unregistered'; Expect = 'GOOD'; Params = @{ members = @('kisa_case_rdp') }
        Verify = { $m = @(Get-LocalGroupMember -SID 'S-1-5-32-555' | Where-Object { $_.Name -like '*\kisa_case_rdp' }); if ($m.Count -eq 1) { $true } else { "kisa_case_rdp 미등록" } }
    }
    # 값 검증 거부: 관리자(지금 실행 중인 계정)는 "관리자 외 별도 계정"이 아니라 아무것도 등록하지 않는다
    FixReject = @{ From = 'rdp-account-unregistered'; Params = @{ members = @('kisa_case_rdp', $env:USERNAME) } }
}
