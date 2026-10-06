"""05_network/parsers/cisco_ios.py — Cisco IOS `show running-config` 텍스트 파싱 헬퍼.

실제 장비 없이 미리 수집된 설정 텍스트 파일만으로 판정하므로(05_network/CLAUDE.md "오프라인
설정파일 분석" 원칙), 이 모듈은 정규식/블록 파싱만 제공하고 판정 로직은 각 checks/cisco_ios/N-xx.py
에 둔다. Cisco IOS 설정에서 하위 명령은 정확히 공백 1칸으로 들여쓰기되고, 최상위 명령/`!` 구분자는
들여쓰기가 없다 — 이 규칙으로 블록(line/interface 등)을 구분한다.
"""
from __future__ import annotations

import re
import secrets
import string


def detect(text: str) -> bool:
    if re.search(r"^version \d+\.\d+", text, re.M):
        return True
    if "Building configuration" in text or "Current configuration" in text:
        return True
    if re.search(r"^hostname \S+", text, re.M) and re.search(r"^interface \S+", text, re.M):
        return True
    return False


def get_blocks(lines: list[str], header_re: str) -> list[list[str]]:
    """header_re 에 매치되는 최상위(들여쓰기 없는) 줄부터, 다음 최상위 줄 전까지를 블록으로 반환."""
    pattern = re.compile(header_re)
    blocks: list[list[str]] = []
    i, n = 0, len(lines)
    while i < n:
        if pattern.match(lines[i]):
            body = [lines[i]]
            j = i + 1
            while j < n and lines[j].startswith(" "):
                body.append(lines[j])
                j += 1
            blocks.append(body)
            i = j
        else:
            i += 1
    return blocks


class Ctx:
    """check 함수에 전달되는 파싱 컨텍스트. 원문 전체 검색 + line/interface 블록 접근을 제공한다."""

    def __init__(self, text: str):
        self.text = text
        self.lines = text.splitlines()
        self.line_blocks = get_blocks(self.lines, r"^line (con|vty|aux|tty) ")
        self.interface_blocks = get_blocks(self.lines, r"^interface \S+")

    def has(self, pattern: str) -> bool:
        return re.search(pattern, self.text, re.M) is not None

    def find(self, pattern: str) -> list:
        return re.findall(pattern, self.text, re.M)

    def search(self, pattern: str):
        return re.search(pattern, self.text, re.M)

    def line_block_text(self, kind: str) -> list[str]:
        """kind: con|vty|aux|tty. 해당 종류의 line 블록들을 각각 하나의 문자열로 합쳐 리스트로 반환."""
        out = []
        for b in self.line_blocks:
            if re.match(rf"^line {kind} ", b[0]):
                out.append("\n".join(b))
        return out

    def ip_interface_blocks(self) -> list[str]:
        """IP 주소가 설정되어 있고 shutdown 되지 않은 인터페이스 블록만 문자열로 반환
        (물리적으로 사용 중인 L3 인터페이스만 대상으로 per-interface 항목을 판정하기 위함)."""
        out = []
        for b in self.interface_blocks:
            body = "\n".join(b)
            if re.search(r"^\s*ip address \d", body, re.M) and not re.search(r"^\s*shutdown\s*$", body, re.M):
                out.append(body)
        return out


def iface_name(block_text: str) -> str:
    """interface/line 블록(문자열, 첫 줄이 헤더)에서 이름만 추출. 예: "interface GigabitEthernet0/1" -> "GigabitEthernet0/1"."""
    first = block_text.splitlines()[0]
    parts = first.split(None, 1)
    return parts[1] if len(parts) > 1 else first


SNMP_DEFAULT_COMMUNITIES = {"public", "private"}


def snmp_community_weak(s: str) -> bool:
    """checks/cisco_ios/N-18.py 와 동일한 복잡성 기준(3종류 이상 조합, 8자리 이상). N-18/19/20의
    fixes/cisco_ios/N-xx.py 가 같은 SNMP community 라인을 서로 다른 조건(문자열 취약/ACL 없음/RW)
    으로 동시에 건드려 재발급 명령이 서로를 덮어쓰는 문제가 있었다(실기 테스트로 발견, N-19/N-20
    주석 참고) - 이 헬퍼로 "문자열이 약한 라인은 N-18이 전담"하도록 책임을 명확히 나눈다."""
    if s.lower() in SNMP_DEFAULT_COMMUNITIES:
        return True
    if len(s) < 8:
        return True
    classes = sum(bool(re.search(p, s)) for p in (r"[A-Z]", r"[a-z]", r"\d", r"[^A-Za-z0-9]"))
    return classes < 3


def gen_secret(length: int = 16) -> str:
    """fixes/cisco_ios/N-xx.py 가 조치 명령어 스크립트에 쓸 임의의 강력한 문자열을 생성한다
    (D-01/WEB-02 의 "모르는 값은 무작위로 새로 설정" 원칙과 동일 - 단, 이 카테고리는 실제 장비에
    적용하지 않고 사람이 검토할 스크립트 파일에만 담기므로 값 자체를 파일에 남겨도 된다)."""
    alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits
    while True:
        s = "".join(secrets.choice(alphabet) for _ in range(length))
        if (any(c.isupper() for c in s) and any(c.islower() for c in s) and any(c.isdigit() for c in s)):
            return s + secrets.choice("!@#$%")
