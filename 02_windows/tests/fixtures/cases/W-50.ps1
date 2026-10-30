# W-50 케이스. 가이드: 양호 = "보안 감사를 로그할 수 없는 경우 즉시 시스템 종료" 사용 안 함 / 취약 = 사용
@{
    States = [ordered]@{
        'crash-on-audit-fail' = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'CrashOnAuditFail'; V = 1 }) }
        'disabled'            = @{ Reg = @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'CrashOnAuditFail'; V = 0 }) }
    }
    Fix    = @{ From = 'crash-on-audit-fail' }
}