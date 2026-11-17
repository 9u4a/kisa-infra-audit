# W-62 케이스(1.7.0 값 지정 조치). 가이드: 불필요한 시작 프로그램 비활성화 - 필요 여부는 사람이 판단하므로 진단은 MANUAL.
# 조치는 정책 값(W-62.entries)에 적은 레지스트리 Run 항목만 지우고(백업 → 원복 시 되살림), 지정하지 않은 항목은 그대로여야 한다.
@{
    States = [ordered]@{
        'run-entries' = @{
            Reg = @(
                @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; N = 'KisaCaseOld'; V = 'cmd.exe /c exit 0'; T = 'String' },
                @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; N = 'KisaCaseKeep'; V = 'cmd.exe /c exit 1'; T = 'String' }
            )
        }
    }
    Fix       = @{
        From = 'run-entries'; Expect = 'MANUAL'; Params = @{ entries = @('KisaCaseOld') }
        Verify = {
            $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            $o = Get-CaseReg -Path $p -Name 'KisaCaseOld'; $k = Get-CaseReg -Path $p -Name 'KisaCaseKeep'
            if ($null -eq $o -and "$k" -eq 'cmd.exe /c exit 1') { $true } else { "old='$o' keep='$k'" }
        }
    }
    # 값 검증 거부: 목록에 없는 이름이 섞이면 아무것도 지우지 않는다
    FixReject = @{ From = 'run-entries'; Params = @{ entries = @('KisaCaseOld', 'KisaCaseNoSuchEntry') } }
}
