# N-10 (중) 로그인 시 경고 메시지 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 로그온 시 접근에 대한 경고 메시지 설정
#                        취약 = 경고 메시지 미설정 또는 시스템 관련 정보 노출
# 자동화 범위(1.4.0, N-R2): 예전에는 배너가 있으면 무조건 MANUAL 이라 양호·"정보 노출" 취약 판정이 불가능했다.
# 배너 본문을 읽어
#   - 배너 없음/본문 비어 있음 또는 시스템 정보 노출(호스트명·$(hostname)/$(domain) 토큰·IP 주소·IOS/버전·
#     장비 제조사/모델 계열명) → VULN
#   - 비인가 접근 경고 문구(가이드 예시의 authorized/monitored 등, 한글 경고·무단·불법·금지)가 있고 노출 없음 → GOOD
#   - 그 밖(배너는 있으나 경고 문구로 볼 단어가 없음) → MANUAL
from parsers import cisco_ios as cio


def check(ctx):
    items = cio.banners(ctx)
    if not items:
        return {"status": "VULN", "detail": "banner motd/login/exec 설정이 없음", "evidence": ""}
    m = ctx.search(r"^hostname (\S+)")
    hostname = m.group(1) if m else None
    evidence = "\n".join(f"[banner {k}]\n{t}" for k, t in items)
    text = "\n".join(t for _, t in items)
    if not text.strip():
        return {"status": "VULN", "detail": "배너가 선언되어 있으나 본문이 비어 있어 경고 메시지가 표시되지 않음", "evidence": evidence}
    leaks = cio.banner_leaks(text, hostname)
    if leaks:
        return {"status": "VULN", "detail": f"배너에 시스템 관련 정보가 노출됨: {', '.join(leaks)}", "evidence": evidence}
    if cio.BANNER_WARN.search(text):
        return {"status": "GOOD", "detail": "비인가 접근 경고 문구가 담긴 배너가 설정되어 있고 시스템 정보 노출이 없음", "evidence": evidence}
    return {"status": "MANUAL", "detail": "배너는 설정되어 있으나 비인가 접근 경고 문구로 볼 단어(authorized/monitored/경고/무단 등)가 없음 - 문구 적절성 수동 확인 필요", "evidence": evidence}
