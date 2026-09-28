# kisa-infra-audit

주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드(2026판)를 기준으로,
Unix/Windows/Web/Network/PC/DBMS 6개 카테고리를 자동 진단하고 보고서를 생성하는 도구입니다.
가능한 항목은 자동 조치(fix)까지 지원합니다.

> ⚠️ 이 저장소는 **개발 진행 중**(SemVer 0.x)입니다. 현재는 Unix(67항목, Linux 대상) 및
> Windows(64항목) 카테고리가 실제 진단 로직으로 구현되어 있고, 나머지 카테고리는 가이드
> 추출·정리본(`guide.json`/`guide.md`)까지만 준비된 상태입니다. 로드맵은 아래를 참고하세요.

## 핵심 원칙
1. **가이드 원문 우선** — 항목명·판단기준·조치방법은 가이드 원문 그대로 사용, 자동화에 꼭 필요한
   경우에만 보완(사유는 `deviation` 필드/CHANGELOG에 기록)
2. **진단/조치 분리** — 진단(`run.*`)은 대상 설정을 절대 변경하지 않음. 조치(`fix.*`)는 별도
   진입점에서 백업·확인 절차를 거쳐 수행
3. **대상 무설치** — 대상 호스트는 OS 기본 도구만 사용 (Unix=POSIX sh, Windows=PowerShell 5.1).
   Python은 분석자 PC 전용(가이드 추출, 네트워크 설정 분석, 다중 호스트 보고서 병합)

> 세부 작업 규칙 문서(`CLAUDE.md`)는 로컬 작업용으로만 관리하며 이 저장소에는 포함하지 않습니다.

## 카테고리 (가이드 장 번호 기준)
| 폴더 | 코드 | 가이드 장 | 항목 수 | 상태 |
|---|---|---|---|---|
| [`01_unix`](./01_unix) | U | 1. UNIX 서버 | 67 | 🟢 67/67 구현 (Linux) |
| [`02_windows`](./02_windows) | W | 2. Windows 서버 | 64 | 🟢 64/64 구현 |
| [`03_web`](./03_web) | WEB | 3. 웹 서비스 | 26 | ⚪ 정리본만 |
| [`05_network`](./05_network) | N | 5. 네트워크 장비 | 38 | ⚪ 정리본만 |
| [`07_pc`](./07_pc) | PC | 7. PC | 18 | ⚪ 정리본만 |
| [`08_dbms`](./08_dbms) | D | 8. DBMS | 26 | ⚪ 정리본만 |

## 빠른 시작
### Unix (Linux rhel/debian)
```sh
sh 01_unix/run.sh -l              # 항목 목록 확인
sudo sh 01_unix/run.sh            # 전체 진단 (환경 자동 감지, root 권장)
sh 01_unix/run.sh -i U-01,U-05    # 특정 항목만
sh 01_unix/run.sh -g 1            # 특정 하위분류만 (1=계정 관리 ... 5=로그 관리)
```

### Windows Server
```powershell
.\02_windows\run.ps1 -ListOnly              # 항목 목록 확인
.\02_windows\run.ps1                        # 전체 진단 (관리자 권한 권장)
.\02_windows\run.ps1 -Items W-01,W-04       # 특정 항목만
.\02_windows\run.ps1 -Group 1               # 특정 하위분류만 (1=계정 관리 ... 5=보안 관리)
```

두 언어 모두 결과는 `output/<host>_<카테고리번호>_<시각>/` 아래 동일한 구조로 생성됩니다:
- `result.json` / `result.csv` — 기계 판독·표계산용
- `report.html` — 브라우저로 열람 (오프라인 단일 파일)
- `summary.txt` / `run.log` — 요약 · 실행 로그

## 가이드 데이터 추출·정리
모든 check/fix 구현은 가이드 PDF가 아니라, 아래 스크립트가 생성한 `guide.json`/`guide.md`를
기준으로 진행합니다 (원본 PDF는 저장소에 포함하지 않습니다).
```sh
python lib/extract_guide.py            # 전체 카테고리
python lib/extract_guide.py --only 01_unix
```

## 로드맵
| 버전 | 내용 |
|---|---|
| 0.1.0 ✅ | 골격, 가이드 추출·정리본 6종, 공통 모듈, 보고서 템플릿, Unix PoC(U-01~05) |
| 0.2.0 ✅ | Unix 67항목 전체 |
| 0.3.0 ✅ | Windows Server 64항목 |
| 0.4.0 | PC 18항목 |
| 0.5.0 | Web 26항목 |
| 0.6.0 | DBMS 26항목 |
| 0.7.0 | Network 38항목 |
| 0.8.0 | 자동 조치(fix) 공통 인프라 + Unix/Windows/PC |
| 0.9.0 | Web/DBMS fix, Network 조치 스크립트, 통합 런처, 다중 호스트 보고서 병합 |
| 1.0.0 | 6개 카테고리 완성·검증 |

## 라이선스 · 출처
- 코드: MIT License ([`LICENSE`](./LICENSE))
- 근거 문서: 한국인터넷진흥원(KISA), 「주요정보통신기반시설 기술적 취약점 분석·평가 방법
  상세가이드」(2026판). 저작권은 원저작자(KISA)에 있으며, 본 저장소는 가이드 원문을 코드로
  옮긴 진단 도구이지 가이드 자체를 재배포하지 않습니다(PDF 미포함).
