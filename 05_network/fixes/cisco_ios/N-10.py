# N-10 (중) 로그인 시 경고 메시지 설정 [Cisco IOS] - 조치 명령어 생성
# checks/cisco_ios/N-10.py: VULN = 배너 없음, 본문이 빈 배너, 또는 배너에 시스템 정보 노출. 가이드 원문이
# 금지하는 "시스템 정보 노출"이 없는 일반적인 경고 문구를 motd 로 제시하고, 정보가 노출되거나 비어 있는
# 기존 login/exec/incoming 배너는 지운다(1.4.0 - 예전에는 motd 만 추가해 노출 배너가 그대로 남았다, N-R2).
from parsers import cisco_ios as cio


def generate(ctx):
    m = ctx.search(r"^hostname (\S+)")
    hostname = m.group(1) if m else None
    cmds = []
    for kind, text in cio.banners(ctx):
        if kind == "motd":
            continue  # 아래 banner motd 가 기존 motd 를 대체한다
        if not text.strip() or cio.banner_leaks(text, hostname):
            cmds.append(f"no banner {kind}")
    cmds += [
        "banner motd ^C",
        "WARNING: Unauthorized access to this device is prohibited.",
        "All activity may be monitored and recorded.",
        "^C",
    ]
    return cmds
