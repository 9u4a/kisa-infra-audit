# W-12 케이스. 가이드: 양호 = "익명 SID/이름 변환 허용" 사용 안 함 / 취약 = 사용.
# 1.7.0: 조치를 manual 에서 auto(secedit LSAAnonymousNameLookup=0)로 바꿨다 - 이 케이스가 같은 secedit 경로로 취약 상태를 만든다.
@{
    States = [ordered]@{
        'anonymous-lookup-on'  = @{ Sec = @{ 'System Access' = @{ LSAAnonymousNameLookup = 1 } } }
        'anonymous-lookup-off' = @{ Sec = @{ 'System Access' = @{ LSAAnonymousNameLookup = 0 } } }
    }
    Fix    = @{ From = 'anonymous-lookup-on' }
}
