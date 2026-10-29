# N-22 (상) Spoofing 방지 필터링 적용 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 경계 라우터/보안장비에 스푸핑 방지 필터링 적용 / 취약 = 미적용
# 자동화 범위: RFC 6890 특수 용도 대역을 4개 이상 차단(deny ip <대역>)하는 ACL(번호형 access-list, 이름형
# ip access-list extended 모두)을 찾는다.
#   - 그런 ACL 이 없음 → VULN
#   - 그런 ACL 이 활성(shutdown 아님) 인터페이스에 inbound(ip access-group <ACL> in)로 적용됨 → GOOD
#     (가이드 조치 Step 3 "SP 와 연결된 인터페이스에 ip access-group <ACL> in" 을 설정에서 직접 확인. 1.4.0 이전에는
#      적용 여부를 보지 않아 양호 판정이 불가능했다 - N-R3)
#   - ACL 은 정의됐으나 인터페이스 inbound 적용을 찾지 못함 → MANUAL(ZBF·class-map 등 다른 방식 적용 여부 확인 필요)
import re

_SPECIAL_NETS = ["0.0.0.0", "10.0.0.0", "127.0.0.0", "169.254.0.0", "172.16.0.0", "192.0.2.0", "192.168.0.0", "224.0.0.0"]
_MIN_NETS = 4


def _acl_denies(ctx) -> dict:
    acls: dict[str, set] = {}
    for acl, net in ctx.find(r"^access-list (\d+) deny[ \t]+ip[ \t]+(\d{1,3}(?:\.\d{1,3}){3})"):
        acls.setdefault(acl, set()).add(net)
    name = None
    for line in ctx.lines:
        m = re.match(r"^ip access-list extended (\S+)", line)
        if m:
            name = m.group(1)
            acls.setdefault(name, set())
            continue
        if not line.startswith(" "):
            name = None
            continue
        if name:
            m = re.match(r"^\s+(?:\d+[ \t]+)?deny[ \t]+ip[ \t]+(\d{1,3}(?:\.\d{1,3}){3})", line)
            if m:
                acls[name].add(m.group(1))
    return acls


def check(ctx):
    acls = _acl_denies(ctx)
    spoof = {acl: sorted(n for n in nets if n in _SPECIAL_NETS) for acl, nets in acls.items()}
    spoof = {acl: nets for acl, nets in spoof.items() if len(nets) >= _MIN_NETS}
    if not spoof:
        return {"status": "VULN", "detail": f"RFC 6890 특수 용도 대역(사설/루프백 등)을 {_MIN_NETS}개 이상 차단하는 스푸핑 방지 ACL을 찾지 못함", "evidence": "없음"}
    evidence = "\n".join(f"ACL {acl}: {', '.join(nets)} 차단" for acl, nets in spoof.items())
    applied = []
    for block in ctx.interface_blocks:
        body = "\n".join(block)
        if re.search(r"^\s*shutdown\s*$", body, re.M):
            continue
        for acl in re.findall(r"^\s*ip access-group (\S+) in[ \t]*$", body, re.M):
            if acl in spoof:
                applied.append(f"{block[0].split(None, 1)[-1]}(ACL {acl} in)")
    if applied:
        return {"status": "GOOD", "detail": f"스푸핑 방지 ACL이 인터페이스 inbound 로 적용됨: {', '.join(applied)} - 적용 위치가 경계(외부 연결) 인터페이스인지 확인 권장", "evidence": evidence + "\n적용: " + ", ".join(applied)}
    return {"status": "MANUAL", "detail": "스푸핑 방지 ACL은 정의되어 있으나 인터페이스 inbound(ip access-group ... in) 적용을 찾지 못함 - 경계 인터페이스 적용 여부 수동 확인 필요", "evidence": evidence}
