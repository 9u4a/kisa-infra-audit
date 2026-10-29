# N-07 (상) Session Timeout 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = Session Timeout 10분 이하 설정 / 취약 = 미설정 또는 10분 초과
# exec-timeout 은 `<분> [<초>]` 이며 `0 0` 은 시간 제한 해제(무제한)라 미설정과 같이 취약으로 본다(N-R1).
from parsers import cisco_ios as cio

LIMIT_SEC = 600


def _fmt(sec):
    if sec is None:
        return "exec-timeout 미설정"
    if sec == 0:
        return "exec-timeout 0 0(시간 제한 없음)"
    return f"exec-timeout={sec // 60}분 {sec % 60}초"


def check(ctx):
    results = []
    for kind in ("con", "vty", "aux"):
        for b in ctx.line_block_text(kind):
            results.append((cio.iface_name(b), cio.exec_timeout_seconds(b)))

    if not results:
        return {"status": "ERROR", "detail": "line con/vty/aux 설정을 찾지 못함", "evidence": ""}

    evidence = "\n".join(f"{k}: {_fmt(v)}" for k, v in results)
    bad = [k for k, v in results if v is None or v == 0 or v > LIMIT_SEC]
    if bad:
        return {"status": "VULN", "detail": f"exec-timeout 이 미설정·무제한(0 0)이거나 10분을 초과하는 라인이 있음: {bad}", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 라인의 exec-timeout이 10분 이하로 설정되어 있음", "evidence": evidence}
