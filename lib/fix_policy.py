#!/usr/bin/env python3
"""lib/fix_policy.py — 조치 정책 파일 파서 (분석자 PC 전용, Python 3.10+, 표준 라이브러리만).

1.6.0 G-01·G-02·G-03·G-06: `fix --policy <파일> --operator <이름>` 의 정책 파일을 읽는다. sh(lib/common_fix.sh)·
PowerShell(lib/Common.psm1) 과 같은 명세(줄 단위 텍스트)를 같은 방식으로 해석해야 한다 - 이 모듈은 Python 진입점
(05_network/fix.py)이 쓰고, 정책 형식 단위 테스트(lib/tests/fix_policy_test.py)의 기준 구현이기도 하다.

형식(UTF-8, BOM·CRLF 허용):
  # 주석 / 빈 줄 무시, 각 줄 앞뒤 공백 제거
  category=05            머리말(첫 [host: 전)에 정확히 1회씩: category·expires(YYYY-MM-DD, 그날까지 유효)·approver(비어 있으면 안 됨)
  expires=2026-12-31
  approver=홍길동
  N-01                   승인 코드(머리말 구역), guide.json 에 있어야 하고 중복 금지
  N-06:irreversible      원복 불가(# 원복:)·업무 영향(# 영향:) 머리말이 있는 조치는 이 플래그가 있어야 적용
  [host:core-sw1]        이 호스트(대소문자 무시)에서 제외할 코드를 -코드 로
  -N-06
  [host:*]               이름이 맞는 구역이 없는 나머지 모든 호스트 허용(제외 줄 가능)

호스트 결정: 같은 이름 구역 → 없으면 [host:*] → 둘 다 없으면 거부("정책에 없는 호스트").
형식 오류는 줄 번호와 함께 모아서 PolicyError 로 알린다(진입점은 exit 2, 아무것도 바꾸지 않음).
"""
from __future__ import annotations

import datetime
import getpass
import hashlib
import os
import re
from dataclasses import dataclass, field

VALID_CATEGORIES = ("01", "02", "03", "05", "07", "08")
HEADER_KEYS = ("category", "expires", "approver")
IRREVERSIBLE = "irreversible"

_CODE_RE = re.compile(r"^([A-Z]+-\d+)(?::(.*))?$")
_EXCL_RE = re.compile(r"^-([A-Z]+-\d+)$")
_HOST_RE = re.compile(r"^\[host:(.*)\]$")
_KV_RE = re.compile(r"^([^=\s]+)\s*=(.*)$")
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class PolicyError(Exception):
    """정책 파일 거부. errors 는 사람이 읽을 메시지 목록(줄 번호 포함)."""

    def __init__(self, errors: list[str]):
        self.errors = list(errors)
        super().__init__("; ".join(self.errors))


@dataclass
class Policy:
    path: str
    sha256: str
    category: str
    expires: str
    approver: str
    approved: dict[str, bool]                      # 코드 -> irreversible 플래그
    hosts: dict[str, set[str]] = field(default_factory=dict)   # 소문자 호스트 이름 -> 제외 코드
    host_names: dict[str, str] = field(default_factory=dict)   # 소문자 -> 파일에 적힌 이름(표시용)
    wildcard: set[str] | None = None               # [host:*] 의 제외 코드, 구역이 없으면 None

    def resolve_host(self, host: str) -> tuple[str, set[str]]:
        """(적용된 구역 표시, 제외 코드) - 정책에 없는 호스트면 PolicyError."""
        key = (host or "").strip().lower()
        if key and key in self.hosts:
            return f"[host:{self.host_names[key]}]", set(self.hosts[key])
        if self.wildcard is not None:
            return "[host:*]", set(self.wildcard)
        raise PolicyError([f"정책에 없는 호스트: {host} ([host:{host}] 구역도 [host:*] 구역도 없음)"])

    def decide(self, code: str, section: str, excluded: set[str], impact_note: str | None) -> tuple[bool, str]:
        """정책 모드 항목 판정 - (적용 여부, 제외 사유). section 은 resolve_host 가 돌려준 구역 표시.
        사유 문구는 sh/PowerShell 과 같다: '정책 미승인' / '정책 미승인(호스트 제외: [host:이름])' /
        'irreversible 플래그 필요: 원복: … / 영향: …'."""
        if code not in self.approved:
            return False, "정책 미승인"
        if code in excluded:
            return False, f"정책 미승인(호스트 제외: {section})"
        if impact_note and not self.approved[code]:
            return False, f"irreversible 플래그 필요: {impact_note}"
        return True, ""


def _read_lines(path: str) -> tuple[list[str], str]:
    with open(path, "rb") as f:
        raw = f.read()
    digest = hashlib.sha256(raw).hexdigest()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise PolicyError([f"{path}: UTF-8 로 읽을 수 없음 ({e})"]) from e
    # \r\n·\r 줄 끝 모두 허용 - 줄 번호는 \n 기준(편집기와 같게)
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n"), digest


def parse_policy(path: str, category: str, valid_codes: set[str] | list[str],
                 today: datetime.date | None = None) -> Policy:
    """정책 파일을 읽어 Policy 를 돌려준다. category 는 실행 카테고리 번호("05" 등), valid_codes 는 해당
    카테고리 guide.json 의 코드 전체. 형식·내용 오류는 줄 번호와 함께 모두 모아 PolicyError."""
    valid = set(valid_codes)
    lines, digest = _read_lines(path)
    errors: list[str] = []
    header: dict[str, tuple[str, int]] = {}
    approved: dict[str, bool] = {}
    hosts: dict[str, set[str]] = {}
    host_names: dict[str, str] = {}
    wildcard: set[str] | None = None
    section: str | None = None   # None = 머리말, 아니면 소문자 호스트 키("*" 포함)

    for no, raw_line in enumerate(lines, 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        m = _HOST_RE.match(line)
        if m:
            name = m.group(1).strip()
            if not name:
                errors.append(f"{no}행: 호스트 이름이 비어 있음: {line}")
                section = "\0invalid"
                continue
            key = name.lower()
            if key == "*":
                if wildcard is not None:
                    errors.append(f"{no}행: [host:*] 구역이 두 번 나옴")
                wildcard = set() if wildcard is None else wildcard
            else:
                if key in hosts:
                    errors.append(f"{no}행: [host:{name}] 구역이 두 번 나옴")
                hosts.setdefault(key, set())
                host_names.setdefault(key, name)
            section = key
            continue
        if section is not None:
            m = _EXCL_RE.match(line)
            if not m:
                errors.append(f"{no}행: [host:] 구역에는 '-코드' 줄만 쓸 수 있음: {line}")
                continue
            code = m.group(1)
            if code not in valid:
                errors.append(f"{no}행: 카테고리 {category} 에 없는 코드: {code}")
                continue
            if section == "\0invalid":
                continue
            target = wildcard if section == "*" else hosts[section]
            if code in target:
                errors.append(f"{no}행: 같은 구역에 제외 코드 중복: {code}")
            target.add(code)
            continue
        # 머리말 구역
        m = _KV_RE.match(line)
        if m and not _CODE_RE.match(line):
            key, value = m.group(1).strip(), m.group(2).strip()
            if key not in HEADER_KEYS:
                errors.append(f"{no}행: 알 수 없는 키: {key} (허용: {', '.join(HEADER_KEYS)})")
            elif key in header:
                errors.append(f"{no}행: {key}= 가 두 번 나옴(처음 {header[key][1]}행)")
            else:
                header[key] = (value, no)
            continue
        m = _CODE_RE.match(line)
        if not m:
            if line.startswith("-") and _EXCL_RE.match(line):
                errors.append(f"{no}행: 제외 줄(-코드)은 [host:] 구역 안에만 쓸 수 있음: {line}")
            else:
                errors.append(f"{no}행: 해석할 수 없는 줄: {line}")
            continue
        code, flag = m.group(1), m.group(2)
        if flag is not None and flag.strip() != IRREVERSIBLE:
            errors.append(f"{no}행: 알 수 없는 플래그: {code}:{flag} (허용: {code}:{IRREVERSIBLE})")
            continue
        if code not in valid:
            errors.append(f"{no}행: 카테고리 {category} 에 없는 코드: {code}")
            continue
        if code in approved:
            errors.append(f"{no}행: 승인 코드 중복: {code}")
            continue
        approved[code] = flag is not None

    for key in HEADER_KEYS:
        if key not in header:
            errors.append(f"머리말에 {key}= 가 없음")
    cat = header.get("category", ("", 0))
    if "category" in header:
        if cat[0] not in VALID_CATEGORIES:
            errors.append(f"{cat[1]}행: category={cat[0]} 은 알 수 없는 카테고리 (허용: {'/'.join(VALID_CATEGORIES)})")
        elif cat[0] != category:
            errors.append(f"{cat[1]}행: 카테고리 불일치: 정책 category={cat[0]}, 실행 카테고리 {category}")
    exp = header.get("expires", ("", 0))
    if "expires" in header:
        try:
            if not _DATE_RE.match(exp[0]):
                raise ValueError(exp[0])
            exp_date = datetime.date.fromisoformat(exp[0])
        except ValueError:
            errors.append(f"{exp[1]}행: expires 형식 오류(YYYY-MM-DD): {exp[0]}")
        else:
            if (today or datetime.date.today()) > exp_date:
                errors.append(f"{exp[1]}행: 정책 유효기간 경과: expires={exp[0]}")
    appr = header.get("approver", ("", 0))
    if "approver" in header and not appr[0]:
        errors.append(f"{appr[1]}행: approver 가 비어 있음")

    if errors:
        raise PolicyError(errors)
    return Policy(path=os.path.abspath(path), sha256=digest, category=cat[0], expires=exp[0], approver=appr[0],
                  approved=approved, hosts=hosts, host_names=host_names, wildcard=wildcard)


def impact_note(fix_file: str) -> str | None:
    """조치 파일 첫 12줄의 '# 원복: ...'(F4)·'# 영향: ...'(F5) 문구. 둘 다 있으면 ' / ' 로 잇는다. 없으면 None."""
    notes = []
    try:
        with open(fix_file, encoding="utf-8-sig") as f:
            head = [next(f, "") for _ in range(12)]
    except OSError:
        return None
    for prefix in ("# 원복: ", "# 영향: "):
        for ln in head:
            ln = ln.rstrip("\r\n")
            if ln.startswith(prefix) and ln[len(prefix):].strip():
                notes.append(f"{prefix[2:4]}: {ln[len(prefix):].strip()}")
                break
    return " / ".join(notes) or None


def login_user() -> str:
    """실제 로그인 사용자(sh 의 SUDO_USER → logname → id -un 과 같은 순서)."""
    u = os.environ.get("SUDO_USER", "").strip()
    if u:
        return u
    try:
        return os.getlogin()
    except OSError:
        pass
    try:
        return getpass.getuser()
    except Exception:  # noqa: BLE001 - 환경 변수가 전혀 없으면 KeyError 등
        return "unknown"


def now_iso() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def audit_header(policy: Policy, operator: str, host: str, category: str, mode: str, started_at: str) -> list[str]:
    """G-03 감사 기록 머리 줄(키=값). 비밀값은 넣지 않는다(S5)."""
    return [
        f"operator={operator}",
        f"login_user={login_user()}",
        f"approver={policy.approver}",
        f"policy_file={policy.path}",
        f"policy_sha256={policy.sha256}",
        f"policy_expires={policy.expires}",
        f"started_at={started_at}",
        f"host={host}",
        f"category={category}",
        f"mode={mode}",
    ]
