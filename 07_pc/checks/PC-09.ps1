# PC-09 (하) 브라우저 종료 시 임시 인터넷 파일 폴더의 내용을 삭제하도록 설정
# 판단 기준(가이드 원문): 양호 = "브라우저를 닫을 때 임시 인터넷 파일 폴더 비우기"가 사용
#                        취약 = 미사용
# 이 설정은 레거시 Internet Explorer 전용 정책이며, Windows 10/11 기본 브라우저인 Edge(Chromium)
# 에는 동일한 단일 레지스트리 스위치가 없어 자동 판정이 불가능하다. 브라우저별로 수동 확인 필요.

return New-CheckResult -Code "PC-09" -Status "MANUAL" `
    -Detail "이 정책은 레거시 Internet Explorer 전용이며 Edge(Chromium) 등 최신 브라우저는 동일한 단일 설정이 없어 자동 판정이 불가능함 — 실제 사용 브라우저의 설정(방문 기록/캐시 삭제 옵션)을 수동 확인 필요"
