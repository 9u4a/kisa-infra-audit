# W-03 케이스(1.7.0 값 지정 조치). 가이드: 불필요한 계정 제거 - "불필요"는 사람이 판단하므로 진단은 MANUAL.
# 조치는 정책 값(W-03.accounts)에 적은 계정만 비활성화하고, 지정하지 않은 계정은 그대로여야 한다.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) Remove-CaseLocalUser 'kisa_case_old'; Remove-CaseLocalUser 'kisa_case_keep' } })
    States    = [ordered]@{
        'extra-account' = @{
            Set   = { New-CaseLocalUser 'kisa_case_old'; New-CaseLocalUser 'kisa_case_keep' }
            Check = {
                $o = Get-LocalUser -Name 'kisa_case_old' -ErrorAction SilentlyContinue; $k = Get-LocalUser -Name 'kisa_case_keep' -ErrorAction SilentlyContinue
                if ($o -and $o.Enabled -and $k -and $k.Enabled) { $true } else { "old=$($o.Enabled) keep=$($k.Enabled)" }
            }
        }
    }
    Fix       = @{
        From = 'extra-account'; Expect = 'MANUAL'; Params = @{ accounts = @('kisa_case_old') }
        Verify = { if (-not (Get-LocalUser 'kisa_case_old').Enabled -and (Get-LocalUser 'kisa_case_keep').Enabled) { $true } else { "old=$((Get-LocalUser 'kisa_case_old').Enabled) keep=$((Get-LocalUser 'kisa_case_keep').Enabled)" } }
    }
    # 값 검증 거부: 지금 실행 중인 계정이 섞이면 아무것도 바꾸지 않는다
    FixReject = @{ From = 'extra-account'; Params = @{ accounts = @('kisa_case_old', $env:USERNAME) } }
}
