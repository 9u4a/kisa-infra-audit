#!/usr/bin/env python3
"""lib/tests/fix_impact.py — 조치 운영 영향 분류표(docs/FIX_IMPACT.md) 생성기(분석자 PC/CI 전용, 1.6.0 G-02).

모든 카테고리의 조치 파일(fixes/**/*.sh·*.ps1) 머리말(앞 12줄)의 "# 원복: ..."(F4, 완전 원복 불가)·"# 영향: ..."(F5, 적용하는
순간 업무 중단 가능)과 guide.json 의 fix 등급을 모아 항목별 표를 만든다. 조치 진입점(lib/common_fix.sh fix_policy_irrev_ok,
lib/Common.psm1)은 같은 머리말을 읽어, 둘 중 하나라도 있으면 정책 파일에 "코드:irreversible" 이 있어야 적용한다 - 이 표가
정책 작성자가 그 플래그가 필요한 항목을 미리 보는 목록이다(구 D4 운영 영향표).

05_network 는 장비에 직접 적용하지 않는 명령어 생성기(fix 등급 전부 manual)라 넣지 않는다.

사용법:
  python lib/tests/fix_impact.py            # docs/FIX_IMPACT.md 다시 생성
  python lib/tests/fix_impact.py --check    # 문서가 머리말·guide.json 과 다르면 exit 1(CI static-analysis) - 다시 생성해 커밋할 것
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "FIX_IMPACT.md"
# 카테고리 → [(계열 하위 폴더, 확장자, 표에 쓸 대상 이름)] - lib/tests/guide_consistency.py FAMILIES 와 같은 단위
FAMILIES = {
    "01_unix": [("", "sh", "Unix(sh)")],
    "02_windows": [("", "ps1", "Windows")],
    "03_web": [("", "sh", "Apache/Nginx/Tomcat(sh)"), ("iis", "ps1", "IIS")],
    "05_network": [("cisco_ios", "py", "Cisco IOS(명령어 생성)")],
    "07_pc": [("", "ps1", "PC")],
    "08_dbms": [("mysql", "sh", "MySQL"), ("postgres", "sh", "PostgreSQL"), ("oracle", "sh", "Oracle"), ("mssql", "ps1", "MSSQL")],
}
TITLES = {"01_unix": "01 Unix 서버", "02_windows": "02 Windows 서버", "03_web": "03 웹 서비스", "05_network": "05 네트워크 장비", "07_pc": "07 PC", "08_dbms": "08 DBMS"}
HEAD_LINES = 12
NOTE_RE = {"rb": re.compile(r"^# 원복: (.*\S)\s*$"), "im": re.compile(r"^# 영향: (.*\S)\s*$")}


def header_notes(path: Path) -> dict[str, str]:
    """앞 12줄에서 처음 나온 원복/영향 표기(진입점 fix_rollback_note·fix_impact_note 와 같은 규칙)."""
    head = path.read_text(encoding="utf-8-sig").splitlines()[:HEAD_LINES]
    out = {}
    for key, rx in NOTE_RE.items():
        for ln in head:
            m = rx.match(ln.rstrip("\r"))
            if m:
                out[key] = m.group(1)
                break
    return out


def cell(s: str) -> str:
    return s.replace("|", "\\|") if s else "-"


def build() -> str:
    lines = [
        "# 조치 운영 영향 분류표 (FIX_IMPACT)",
        "",
        "> 이 문서는 `python lib/tests/fix_impact.py` 가 조치 파일 머리말과 guide.json 에서 생성한다 - 손으로 고치지 말 것.",
        "> CI(static-analysis)가 `--check` 로 최신인지 확인한다.",
        "",
        "- **원복 불가 사유**: 조치 파일 머리말 `# 원복:` (운영 안전 기준 F4 - 백업으로 완전히 되돌릴 수 없음)",
        "- **업무 영향**: 조치 파일 머리말 `# 영향:` (F5 - 적용하는 순간 서비스 중지·세션 끊김·계정 잠금·접근 차단·재시작 등 업무가 끊길 수 있음)",
        "- **:irreversible**: 둘 중 하나라도 있으면 정책 모드(`fix --policy`)에서 정책 파일에 `코드:irreversible` 로 적어야 적용된다"
        "(없으면 `POLICY_SKIPPED`). 대화형 실행에는 영향 없음.",
        "- **param(키)**: 값 지정 조치(1.7.0) - 정책 파일 호스트 구역의 `코드.키 = 값` 이 있을 때만 정책 모드로 적용한다(대화형·값 없음은 수동 안내).",
        "",
    ]
    total = need = 0
    sections: list[str] = []
    for cat, fams in FAMILIES.items():
        items = {i["code"]: i for i in json.loads((ROOT / cat / "guide.json").read_text(encoding="utf-8"))["items"]}
        rows = []
        for fam, ext, label in fams:
            d = ROOT / cat / "fixes" / fam
            if not d.is_dir():
                continue
            for f in sorted(d.glob(f"*.{ext}"), key=lambda p: (p.stem.split("-")[0], int(p.stem.split("-")[-1]))):
                it = items.get(f.stem, {})
                n = header_notes(f)
                irr = bool(n.get("rb") or n.get("im"))
                total += 1
                need += irr
                grade = it.get("fix", "-")
                if grade == "param":   # 1.7.0 값 지정 조치: 정책 파일에서 받는 키를 함께 보여 준다
                    grade = f"param({it.get('fix_params', '')})"
                rows.append(f"| {f.stem} | {label} | {cell(it.get('title', ''))} | {grade} | {cell(n.get('rb', ''))} | "
                            f"{cell(n.get('im', ''))} | {'필요' if irr else '-'} |")
        if not rows:
            continue
        n_irr = sum(1 for r in rows if r.endswith("| 필요 |"))
        sections += [f"## {TITLES[cat]} ({len(rows)}개 조치, :irreversible 필요 {n_irr}개)", "",
                     "| 코드 | 대상 | 제목 | 등급 | 원복 불가 사유 | 업무 영향 | :irreversible |",
                     "|---|---|---|---|---|---|---|", *rows, ""]
    lines += [f"전체 조치 {total}개 중 정책에 `:irreversible` 이 필요한 조치 {need}개.", "", *sections]
    return "\n".join(lines).rstrip("\n") + "\n"


OUT_APPROVAL = ROOT / "docs" / "APPROVAL_REQUIRED.md"
# 자동 조치가 없는(fix=manual) 항목 중 guide.json deviation 에 사유가 없는 것의 근거(1.7.0)
MANUAL_REASON = {
    "U-49": "BIND 패치 적용 - 버전 선택·서비스 재시작이 필요하고 패치 자동 적용은 자동화 범위 밖(사용자 결정, 1.7.0 기획)",
    "U-64": "OS 패치 적용 - 재부팅·서비스 영향, 적용 시점·대상은 패치 관리 절차로 정한다(자동화 범위 밖)",
    "W-27": "최신 OS 빌드 설치 - 재부팅 필요, 업그레이드 시점은 운영 판단(자동화 범위 밖)",
    "W-38": "Windows 보안 패치 적용 - 재부팅·서비스 영향(자동화 범위 밖)",
    "W-45": "백신 제품 선택·설치는 스크립트가 대신할 수 없음(소프트웨어 설치는 자동화 대상 아님)",
    "WEB-11": "DocumentRoot 분리는 사이트 콘텐츠 이전과 설정 갱신이 필요한 사실상의 사이트 재배치 - 대상 경로를 스크립트가 정할 수 없음",
    "PC-08": "어느 부트 항목(다른 OS)을 지워도 되는지 스크립트가 판단할 수 없음 - OS 삭제는 데이터 손실 위험",
    "WEB-24": "업로드 경로는 애플리케이션마다 달라 조치 대상(경로·권한)을 스크립트가 정할 수 없음",
    "WEB-25": "웹 서버 엔진 패치 - 버전 업그레이드·재시작이 필요(자동화 범위 밖)",
    "PC-09": "IE 전용 설정이라 Edge 에 같은 설정이 없음 - 대상 브라우저 환경을 사람이 확인",
    "PC-10": "Windows 핫픽스 적용 - 재부팅 영향(자동화 범위 밖)",
    "PC-11": "지원 OS 빌드로의 업그레이드 - 재부팅·사용자 영향(자동화 범위 밖)",
    "D-06": "공용 계정 여부는 DB 에서 알 수 없고, 조치가 사람별 계정 생성이라 계정·비밀번호를 스크립트가 만들 수 없음",
    "D-20": "객체 소유자 변경은 애플리케이션 스키마를 재구성하는 작업 - 영향 범위를 앱 담당자가 판단",
    "D-25": "DB 엔진 패치·업그레이드 - 재시작·호환성 영향(자동화 범위 밖)",
}
# 1.7.0 값 지정 조치 기획에서 보류한 항목(남은 위험)
DEFERRED = {
    "U-28": "방화벽 규칙을 바꾸면 원격 관리 접속이 끊길 수 있다(lockout). 자동 원복 타이머(1.8.0 기획) 없이 자동화하지 않는다",
    "W-61": "FAT→NTFS 변환은 되돌릴 수 없고 재부팅·데이터 손상 위험이 있다 - 사람이 백업 확인 후 직접 실행",
    "PC-07": "W-61 과 같은 이유(FAT→NTFS 변환 비가역)",
    "PC-06": "메신저 제품마다 제거 방법이 달라 안전한 무인 제거 경로가 없다",
}


def rollback_class(rb: str) -> str:
    if rb.startswith("불가"):
        return "원복 불가"
    if rb.startswith("일부"):
        return "일부 원복"
    if rb.startswith("실행 단위"):
        return "실행 단위 원복"
    return "원복 제한"


def build_approval() -> str:
    """docs/APPROVAL_REQUIRED.md - 운영자 승인이 필요한 조치와 근거(1.7.0). 근거는 조치 파일 머리말과 guide.json 에서 그대로 가져온다."""
    irrev: list[str] = []
    impact: list[str] = []
    excluded: list[str] = []
    counts: dict[str, dict[str, int]] = {}
    for cat, fams in FAMILIES.items():
        if cat == "05_network":
            continue
        items = {i["code"]: i for i in json.loads((ROOT / cat / "guide.json").read_text(encoding="utf-8"))["items"]}
        c = counts.setdefault(TITLES[cat], {"원복 불가": 0, "일부 원복": 0, "실행 단위 원복": 0, "원복 제한": 0, "업무 영향만": 0})
        for fam, ext, label in fams:
            d = ROOT / cat / "fixes" / fam
            if not d.is_dir():
                continue
            for f in sorted(d.glob(f"*.{ext}"), key=lambda p: (p.stem.split("-")[0], int(p.stem.split("-")[-1]))):
                it = items.get(f.stem, {})
                n = header_notes(f)
                grade = it.get("fix", "-")
                if grade == "param":
                    grade = f"param({it.get('fix_params', '')})"
                row = f"| {f.stem} | {label} | {cell(it.get('title', ''))} | {grade} |"
                if n.get("rb"):
                    k = rollback_class(n["rb"])
                    c[k] += 1
                    irrev.append(f"{row} {k} | {cell(n['rb'])} | {cell(n.get('im', ''))} |")
                elif n.get("im"):
                    c["업무 영향만"] += 1
                    impact.append(f"{row} {cell(n['im'])} |")
        for code, it in sorted(items.items(), key=lambda kv: (kv[0].split("-")[0], int(kv[0].split("-")[-1]))):
            if it.get("fix") != "manual":
                continue
            why = DEFERRED.get(code) or MANUAL_REASON.get(code) or it.get("deviation") or "가이드 판단기준이 조직·업무 판단을 요구"
            tag = "보류(1.7.0)" if code in DEFERRED else "manual"
            excluded.append(f"| {code} | {cell(it.get('title', ''))} | {tag} | {cell(why)} |")
    total_irrev = len(irrev)
    lines = [
        "# 운영자 승인이 필요한 조치와 근거 (APPROVAL_REQUIRED)",
        "",
        "> 이 문서는 `python lib/tests/fix_impact.py` 가 조치 파일 머리말(`# 원복:`·`# 영향:`)과 guide.json 에서 생성한다 - 손으로 고치지 말 것.",
        "> CI(static-analysis)가 `--check` 로 최신인지 확인한다. 항목별 표 전체는 docs/FIX_IMPACT.md.",
        "",
        "## 1. 승인 원칙",
        "",
        "- **위험 조치는 자동(auto) 등급이 될 수 없다**: 완전 원복이 안 되거나(`# 원복:`) 적용하는 순간 업무가 끊길 수 있는(`# 영향:`) 조치는",
        "  `confirm`(또는 값 지정 `param`)이다. CI 의 guide_consistency R8 이 이 규칙을 강제한다 - auto 는 일괄 실행에서 항목별 확인 없이 적용되기 때문이다.",
        "- **대화형 실행**: confirm 은 항목마다 운영자가 `y` 를 입력해야 적용된다. `--yes`/`-Yes` 는 처음의 전체 목록 확인만 생략하고 항목별",
        "  확인은 생략하지 않는다. 터미널이 없는 비대화형 실행에서는 적용하지 않고 `DECLINED` 로 남긴다.",
        "- **정책 모드(무인)**: 승인자가 정책 파일에 적은 항목만 적용한다. 위험 조치는 `코드:irreversible` 로 적어야 하고, 없으면 `POLICY_SKIPPED`.",
        "  승인자·실행자·정책 파일 SHA-256 이 audit.txt 에 남는다.",
        "- **값 지정 조치(param)**: 무엇을 바꿀지(계정·파일·IP 등) 승인자가 정책 파일에 적어야만 적용되며, 값이 하나라도 틀리면 아무것도 바꾸지 않는다.",
        "- **자동 조치 없음(manual)·보류**: 아래 5장 - 도구는 근거만 보여 주고 사람이 직접 조치한다.",
        "",
        "## 2. 요약",
        "",
        "| 카테고리 | 원복 불가 | 일부 원복 | 실행 단위 원복 | 원복 제한(기타) | 업무 영향만(원복 가능) |",
        "|---|---|---|---|---|---|",
        *[f"| {k} | {v['원복 불가']} | {v['일부 원복']} | {v['실행 단위 원복']} | {v['원복 제한']} | {v['업무 영향만']} |" for k, v in counts.items()],
        "",
        "- 원복 불가: 되돌릴 경로가 없음(삭제·비밀번호 재설정·버전 업데이트 등). 일부 원복: 설정은 되돌리지만 끊긴 세션·종료한 프로세스 등은 남음.",
        "  실행 단위 원복: 보안 정책(secedit)처럼 항목별로는 못 되돌리고 그 실행 전체를 `--rollback`/`-Rollback` 해야 함.",
        "- 05 네트워크 장비는 조치가 장비에 적용되지 않는 명령어 생성이라(운영자가 직접 입력) 이 문서에서 뺐다 - docs/FIX_IMPACT.md 참고.",
        "",
        f"## 3. 원복이 완전하지 않은 조치 ({total_irrev}개)",
        "",
        "| 코드 | 대상 | 제목 | 등급 | 원복 | 원복 근거 | 업무 영향 |",
        "|---|---|---|---|---|---|---|",
        *irrev,
        "",
        f"## 4. 원복은 되지만 적용 순간 업무 영향이 있는 조치 ({len(impact)}개)",
        "",
        "| 코드 | 대상 | 제목 | 등급 | 업무 영향(승인 근거) |",
        "|---|---|---|---|---|",
        *impact,
        "",
        f"## 5. 자동 조치에서 제외한 항목과 근거 ({len(excluded)}개)",
        "",
        "| 코드 | 제목 | 구분 | 근거 |",
        "|---|---|---|---|",
        *excluded,
    ]
    return "\n".join(lines).rstrip("\n") + "\n"


def main() -> int:
    outputs = [(OUT, build()), (OUT_APPROVAL, build_approval())]
    if "--check" in sys.argv[1:]:
        bad = 0
        for out, text in outputs:
            cur = out.read_text(encoding="utf-8") if out.is_file() else ""
            if cur != text:
                print(f"FAIL: {out.relative_to(ROOT)} 가 최신이 아님 - python lib/tests/fix_impact.py 로 다시 생성해 커밋할 것")
                bad = 1
            else:
                print(f"OK: {out.relative_to(ROOT)} 최신")
        return bad
    for out, text in outputs:
        out.parent.mkdir(parents=True, exist_ok=True)
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print(f"생성: {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
