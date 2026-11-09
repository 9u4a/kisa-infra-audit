#!/usr/bin/env python3
"""lib/tests/fix_policy_test.py — lib/fix_policy.py(조치 정책 파일 파서) 단위 테스트 (분석자 PC/CI 전용).

1.6.0 G-01·G-06: sh·PowerShell·Python 이 같은 명세로 정책 파일을 해석해야 하므로, 이 테스트가 Python 쪽 기준 해석을
고정한다 - 정상(승인·irreversible·[host:이름]·[host:*]·대소문자 무시), 거부(category 불일치·만료·중복·없는 코드·알 수
없는 키/플래그·머리말 누락·구역 밖 제외 줄·호스트 미등록), BOM/CRLF.
CI: 05_network/tests/run_tests.py 가 끝에서 이 파일을 실행한다(network job).

사용법: python lib/tests/fix_policy_test.py   (exit 0 = 전부 통과)
"""
from __future__ import annotations

import datetime
import os
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "lib"))

import fix_policy as fp  # noqa: E402

CODES = {f"N-{i:02d}" for i in range(1, 39)}
TODAY = datetime.date(2026, 11, 9)
HEAD = "category=05\nexpires=2026-12-31\napprover=홍길동\n"


def write(tmp: str, name: str, text: str, raw: bytes | None = None) -> str:
    p = os.path.join(tmp, name)
    with open(p, "wb") as f:
        f.write(raw if raw is not None else text.encode("utf-8"))
    return p


def parse(path: str, category: str = "05", today: datetime.date = TODAY):
    return fp.parse_policy(path, category, CODES, today=today)


def main() -> int:
    fails: list[str] = []
    n = 0

    def ok(name: str, cond: bool, info: str = "") -> None:
        nonlocal n
        n += 1
        if not cond:
            fails.append(f"{name} {info}".strip())

    def rejected(name: str, text: str, want: str, raw: bytes | None = None, **kw) -> None:
        nonlocal n
        n += 1
        p = write(tmp, f"r{n}.txt", text, raw)
        try:
            parse(p, **kw)
        except fp.PolicyError as e:
            if not any(want in m for m in e.errors):
                fails.append(f"{name}: 거부 사유에 '{want}' 없음: {e.errors}")
            return
        fails.append(f"{name}: 거부돼야 하는데 통과")

    with tempfile.TemporaryDirectory() as tmp:
        # ---- 정상 ---------------------------------------------------------------------------------------
        text = ("# 운영 정책\n" + HEAD + "  N-01  \nN-06:irreversible\n\nN-26\n"
                "[host:Core-SW1]\n-N-26\n# 주석\n[host:*]\n-N-01\n")
        pol = parse(write(tmp, "ok.txt", text))
        ok("정상: 머리말", (pol.category, pol.expires, pol.approver) == ("05", "2026-12-31", "홍길동"))
        ok("정상: 승인 목록", pol.approved == {"N-01": False, "N-06": True, "N-26": False}, str(pol.approved))
        sec, ex = pol.resolve_host("core-sw1")
        ok("정상: [host:이름] 대소문자 무시", (sec, ex) == ("[host:Core-SW1]", {"N-26"}), f"{sec} {ex}")
        sec, ex = pol.resolve_host("other-rtr")
        ok("정상: [host:*] 적용", (sec, ex) == ("[host:*]", {"N-01"}), f"{sec} {ex}")
        ok("정상: sha256 64자", len(pol.sha256) == 64)
        ok("정상: 절대 경로", os.path.isabs(pol.path))
        # decide: 미승인 / 호스트 제외 / irreversible 필요 / 플래그 있으면 통과
        S = "[host:Core-SW1]"
        ok("decide 미승인", pol.decide("N-02", S, set(), None) == (False, "정책 미승인"))
        ok("decide 호스트 제외", pol.decide("N-26", S, {"N-26"}, None) == (False, "정책 미승인(호스트 제외: [host:Core-SW1])"))
        ok("decide irreversible 필요", pol.decide("N-01", S, set(), "영향: x") == (False, "irreversible 플래그 필요: 영향: x"))
        ok("decide irreversible 플래그 있음", pol.decide("N-06", S, set(), "영향: x") == (True, ""))
        ok("decide 머리말 없는 승인 항목", pol.decide("N-26", S, set(), None) == (True, ""))
        # 대소문자: 코드·플래그·머리말 키는 구분(호스트 이름만 무시)
        rejected_cases = [("소문자 코드", HEAD + "n-01\n[host:*]\n", "해석할 수 없는 줄"),
                          ("대문자 플래그", HEAD + "N-01:IRREVERSIBLE\n[host:*]\n", "알 수 없는 플래그"),
                          ("대문자 키", HEAD + "Approver=x\nN-01\n[host:*]\n", "알 수 없는 키")]
        # 유효기간 당일은 유효
        ok("정상: expires 당일 유효", parse(write(tmp, "today.txt", HEAD.replace("2026-12-31", "2026-11-09") + "N-01\n[host:*]\n")).expires == "2026-11-09")
        # BOM + CRLF
        raw = ("﻿" + (HEAD + "N-01:irreversible\n[host:r1]\n-N-01\n")).replace("\n", "\r\n").encode("utf-8")
        pol = parse(write(tmp, "bomcrlf.txt", "", raw))
        ok("BOM/CRLF: 머리말·코드", pol.approver == "홍길동" and pol.approved == {"N-01": True}, str(pol.approved))
        ok("BOM/CRLF: 호스트 구역", pol.resolve_host("R1") == ("[host:r1]", {"N-01"}))
        # 호스트 구역이 없으면 / 이름이 안 맞고 [host:*] 도 없으면 거부
        pol = parse(write(tmp, "nohost.txt", HEAD + "N-01\n[host:r1]\n"))
        try:
            pol.resolve_host("r2")
            ok("호스트 미등록 거부", False, "통과함")
        except fp.PolicyError as e:
            ok("호스트 미등록 거부", "정책에 없는 호스트" in e.errors[0], str(e.errors))

        # ---- 거부 ---------------------------------------------------------------------------------------
        for name, text, want in rejected_cases:
            rejected(name, text, want)
        rejected("category 불일치", HEAD + "N-01\n[host:*]\n", "카테고리 불일치", category="01")
        rejected("알 수 없는 category", HEAD.replace("=05", "=04") + "N-01\n[host:*]\n", "알 수 없는 카테고리")
        rejected("유효기간 경과", HEAD.replace("2026-12-31", "2026-11-08") + "N-01\n[host:*]\n", "유효기간 경과")
        rejected("expires 형식", HEAD.replace("2026-12-31", "2026/12/31") + "N-01\n[host:*]\n", "expires 형식 오류")
        rejected("expires 없는 날짜", HEAD.replace("2026-12-31", "2026-02-30") + "N-01\n[host:*]\n", "expires 형식 오류")
        rejected("approver 비어 있음", HEAD.replace("홍길동", "") + "N-01\n[host:*]\n", "approver 가 비어 있음")
        rejected("approver 누락", "category=05\nexpires=2026-12-31\nN-01\n[host:*]\n", "approver= 가 없음")
        rejected("키 중복", HEAD + "approver=김철수\nN-01\n[host:*]\n", "approver= 가 두 번")
        rejected("알 수 없는 키", HEAD + "owner=x\nN-01\n[host:*]\n", "알 수 없는 키: owner")
        rejected("코드 중복", HEAD + "N-01\nN-01:irreversible\n[host:*]\n", "승인 코드 중복: N-01")
        rejected("없는 코드", HEAD + "N-99\n[host:*]\n", "없는 코드: N-99")
        rejected("다른 카테고리 코드", HEAD + "U-01\n[host:*]\n", "없는 코드: U-01")
        rejected("제외 줄의 없는 코드", HEAD + "N-01\n[host:r1]\n-N-77\n", "없는 코드: N-77")
        rejected("알 수 없는 플래그", HEAD + "N-01:force\n[host:*]\n", "알 수 없는 플래그")
        rejected("머리말의 제외 줄", HEAD + "-N-01\n[host:*]\n", "[host:] 구역 안에만")
        rejected("구역 안 승인 줄", HEAD + "N-01\n[host:r1]\nN-02\n", "'-코드' 줄만")
        rejected("구역 안 키", HEAD + "N-01\n[host:r1]\napprover=x\n", "'-코드' 줄만")
        rejected("해석 불가 줄", HEAD + "N-01 N-02\n[host:*]\n", "해석할 수 없는 줄")
        rejected("빈 호스트 이름", HEAD + "N-01\n[host:]\n", "호스트 이름이 비어 있음")
        rejected("같은 호스트 구역 두 번", HEAD + "N-01\n[host:r1]\n[host:R1]\n", "두 번 나옴")
        rejected("[host:*] 두 번", HEAD + "N-01\n[host:*]\n[host:*]\n", "두 번 나옴")
        rejected("제외 중복", HEAD + "N-01\n[host:r1]\n-N-01\n-N-01\n", "제외 코드 중복")
        rejected("UTF-8 아님", "", "UTF-8", raw=("category=05\napprover=" + "가나").encode("cp949"))
        # 오류는 줄 번호와 함께, 여러 개를 한 번에 보고
        p = write(tmp, "multi.txt", HEAD + "N-99\nowner=x\n[host:*]\n")
        try:
            parse(p)
            ok("여러 오류 줄 번호", False, "통과함")
        except fp.PolicyError as e:
            ok("여러 오류 줄 번호", any(m.startswith("4행:") for m in e.errors) and any(m.startswith("5행:") for m in e.errors),
               str(e.errors))

        # ---- 조치 파일 머리말(G-02) ------------------------------------------------------------------------
        f1 = write(tmp, "fix1.py", "# N-01 x\n# 영향: 접속 끊김\n# 원복: 일부\n")
        ok("impact_note 원복+영향", fp.impact_note(f1) == "원복: 일부 / 영향: 접속 끊김", str(fp.impact_note(f1)))
        f2 = write(tmp, "fix2.py", "# N-02 x\n" + "#\n" * 12 + "# 영향: 13번째 줄\n")
        ok("impact_note 12줄 밖 무시", fp.impact_note(f2) is None)
        ok("impact_note 없는 파일", fp.impact_note(os.path.join(tmp, "none.py")) is None)
        net = os.path.join(ROOT, "05_network", "fixes", "cisco_ios")
        ok("05 N-08 영향 머리말", (fp.impact_note(os.path.join(net, "N-08.py")) or "").startswith("영향: "))
        ok("05 N-16 영향 머리말 없음", fp.impact_note(os.path.join(net, "N-16.py")) is None)

        # ---- 감사 머리 줄(G-03) --------------------------------------------------------------------------
        pol = parse(write(tmp, "audit.txt", HEAD + "N-01\n[host:*]\n"))
        hdr = fp.audit_header(pol, "op", "r1", "05", "apply", "2026-11-09T10:00:00+09:00")
        keys = [h.split("=", 1)[0] for h in hdr]
        ok("감사 키 순서", keys == ["operator", "login_user", "approver", "policy_file", "policy_sha256", "policy_expires",
                                 "started_at", "host", "category", "mode"], str(keys))

    if fails:
        print(f"FAIL: fix_policy_test {len(fails)}/{n}건")
        for f in fails:
            print(f"  - {f}")
        return 1
    print(f"PASS: fix_policy_test {n}건 (정상·[host:이름]/[host:*]·BOM/CRLF·거부 사유·줄 번호·영향 머리말·감사 키)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
