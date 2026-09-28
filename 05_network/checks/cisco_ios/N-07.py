# N-07 (상) Session Timeout 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = Session Timeout 10분 이하 설정 / 취약 = 미설정 또는 10분 초과
import re


def check(ctx):
    results = []
    for kind in ("con", "vty", "aux"):
        blocks = ctx.line_block_text(kind)
        for b in blocks:
            m = re.search(r"^\s*exec-timeout (\d+) (\d+)", b, re.M)
            if not m:
                results.append((kind, None))
            else:
                results.append((kind, int(m.group(1))))

    if not results:
        return {"status": "ERROR", "detail": "line con/vty/aux 설정을 찾지 못함", "evidence": ""}

    evidence = "\n".join(f"{k}: exec-timeout={v}분" if v is not None else f"{k}: exec-timeout 미설정" for k, v in results)
    bad = [k for k, v in results if v is None or v > 10]
    if bad:
        return {"status": "VULN", "detail": f"exec-timeout 이 미설정이거나 10분을 초과하는 라인이 있음: {bad}", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 라인의 exec-timeout이 10분 이하로 설정되어 있음", "evidence": evidence}
