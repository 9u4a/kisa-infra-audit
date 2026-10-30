# W-59 케이스. 가이드: 양호 = "NTLMv2 응답만 보냄"(3) 이상 / 취약 = LM·NTLM 허용(0~2). 값이 없으면 Vista/2008 이후 기본값 3(check 주석)
@{
    States = [ordered]@{
        'lm-ntlm'     = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'LmCompatibilityLevel'; V = 1 }) }
        'ntlmv2-only' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'LmCompatibilityLevel'; V = 3 }) }
        'refuse-lm'   = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'LmCompatibilityLevel'; V = 5 }) }
    }
    Fix    = @{ From = 'lm-ntlm' }
}