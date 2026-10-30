# W-12 케이스. 가이드: 양호 = "익명 SID/이름 변환 허용" 사용 안 함 / 취약 = 사용. 조치는 manual(조치 스크립트 없음)
@{
    States = [ordered]@{
        'anonymous-lookup-on'  = @{ Sec = @{ 'System Access' = @{ LSAAnonymousNameLookup = 1 } } }
        'anonymous-lookup-off' = @{ Sec = @{ 'System Access' = @{ LSAAnonymousNameLookup = 0 } } }
    }
}
