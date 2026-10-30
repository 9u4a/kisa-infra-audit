# W-42 케이스. 가이드: 양호 = 최대 로그 크기 10,240KB 이상 / 취약 = 10,240KB 미만(2008 이상은 덮어쓰기 기간 지정이 없어 크기만 판정 - check 주석).
# 조치(Limit-EventLog)는 되돌리지 못한다(Register-FixNoRollback) - 원복 후 판정은 GOOD, EventLog 레지스트리 차이는 참고.
# 취약 상태는 wevtutil sl /ms 로 만든다(Limit-EventLog 로는 Application 크기가 바뀌지 않았다 - CI run 40981289087).
# 케이스 원복은 세 로그의 채널 최대 크기와 MaxSize 레지스트리 값을 그대로 되돌린다.
@{
    Resources = @(@{
            Save    = { foreach ($n in 'Application', 'System', 'Security') { [PSCustomObject]@{ N = $n; Bytes = (Get-WinEvent -ListLog $n).MaximumSizeInBytes; Reg = (Get-CaseReg "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$n" 'MaxSize'); Upper = (Get-CaseReg "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$n" 'MaxSizeUpper') } } }
            Restore = {
                param($s)
                foreach ($o in @($s)) {
                    if ((Get-WinEvent -ListLog $o.N).MaximumSizeInBytes -ne $o.Bytes) { & wevtutil.exe sl $o.N "/ms:$($o.Bytes)"; if ($LASTEXITCODE -ne 0) { throw "wevtutil sl $($o.N) 실패" } }
                    $k = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$($o.N)"
                    if ("$(Get-CaseReg $k 'MaxSize')" -ne "$($o.Reg)") { Set-CaseReg $k 'MaxSize' $(if ($null -ne $o.Reg) { [int]$o.Reg } else { $null }) 'DWord' }
                    if ("$(Get-CaseReg $k 'MaxSizeUpper')" -ne "$($o.Upper)") { Set-CaseReg $k 'MaxSizeUpper' $(if ($null -ne $o.Upper) { [int]$o.Upper } else { $null }) 'DWord' }
                }
            }
        })
    States    = [ordered]@{
        'application-4mb' = @{
            Set   = { & wevtutil.exe sl Application /ms:4194304; if ($LASTEXITCODE -ne 0) { throw "wevtutil sl Application 실패(rc=$LASTEXITCODE)" } }
            Check = { $s = (Get-WinEvent -ListLog Application).MaximumSizeInBytes; if ($s -eq 4MB) { $true } else { "Application=$s" } }
        }
        'all-10mb-plus'   = @{
            Set   = { foreach ($n in 'Application', 'System', 'Security') { if ((Get-WinEvent -ListLog $n).MaximumSizeInBytes -lt 10MB) { & wevtutil.exe sl $n /ms:10485760 } } }
            Check = { $small = @(foreach ($n in 'Application', 'System', 'Security') { $s = (Get-WinEvent -ListLog $n).MaximumSizeInBytes; if ($s -lt 10MB) { "$n=$s" } }); if ($small.Count -eq 0) { $true } else { $small -join ' ' } }
        }
    }
    Fix       = @{ From = 'application-4mb'; AfterRollback = 'GOOD'; SoftLines = @('\\Services\\EventLog\\') }
}