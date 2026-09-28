# N-18 (상) SNMP Community String 복잡성 설정 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = SNMP 비활성화, 또는 Community String이 영대소문자/숫자/특수문자
#                        중 3종류 이상 조합 8자리 이상 / 취약 = public/private 기본값 또는
#                        복잡성 기준 미달
import re

_DEFAULTS = {"public", "private"}


def _complexity_ok(s):
    if len(s) < 8:
        return False
    classes = 0
    classes += 1 if re.search(r"[A-Z]", s) else 0
    classes += 1 if re.search(r"[a-z]", s) else 0
    classes += 1 if re.search(r"\d", s) else 0
    classes += 1 if re.search(r"[^A-Za-z0-9]", s) else 0
    return classes >= 3


def check(ctx):
    communities = ctx.find(r"^snmp-server community (\S+)")
    if not communities:
        return {"status": "NA", "detail": "SNMP community 설정이 없음(SNMP 미사용)", "evidence": ""}
    # Community String은 비밀번호에 준하는 값이라 평문을 증적에 남기지 않고 길이/기본값 여부만 남긴다
    # (08_dbms 의 "접속정보 원문 미저장" 원칙과 동일).
    evidence = "\n".join(f"길이={len(c)}, 기본값(public/private)={c.lower() in _DEFAULTS}, 복잡성 충족={_complexity_ok(c)}" for c in communities)
    weak = [c for c in communities if c.lower() in _DEFAULTS or not _complexity_ok(c)]
    if weak:
        return {"status": "VULN", "detail": f"기본값(public/private) 또는 복잡성 기준 미달 Community String 존재: {len(weak)}건", "evidence": evidence}
    return {"status": "GOOD", "detail": "모든 Community String이 복잡성 기준(3종류 이상 조합, 8자리 이상)을 충족함", "evidence": evidence}
