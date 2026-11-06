# lib/ — 공통 모듈

모든 카테고리(`NN_*/`)가 공유하는 코드. 카테고리 폴더에는 이 모듈들을 재사용하는
`run.*`/`fix.*`/`checks/*`/`fixes/*`만 두고, 로그·진행표시·환경감지·보고서 생성 같은
공통 기능은 여기에만 구현한다.

`common.sh` 는 1.5.0 D3 에서 넷으로 나눴다. 호출부는 지금처럼 `common.sh` 하나만 source 하면 되고, 나머지 세 파일은
`common.sh` 가 같은 폴더(`$LIB_DIR`, 없으면 `lib`)에서 불러온다. 대상 호스트에는 `lib/` 폴더를 통째로 둔다.

| 파일 | 대상 | 역할 |
|---|---|---|
| `common.sh` | Unix 계열 카테고리(01, 03의 Unix 엔진, 08의 Unix DBMS) | 로그, 색상, 진행 표시, `uname`/`os-release` 기반 환경 감지, `guide.json` 조회(`guide_field`/`guide_list_codes`), 결과 JSON(NDJSON→최종 JSON)/CSV/`summary.txt` 생성, `report.html` 렌더링 |
| `common_web.sh` | 03_web(Unix 엔진) — `common.sh` 가 source | 웹 엔진 자동 탐지·설정 경로 조회, XML 주석 제거·속성 파싱 |
| `common_db.sh` | 08_dbms(Unix DBMS) — `common.sh` 가 source | 엔진 탐지, 운영 안전장치(시간 제한·계정 잠금 방지), 원격 판별, 권한 사전 확인, MySQL/PostgreSQL/Oracle 접속·쿼리, DB 재기동·Oracle 정적 파라미터 복구, SQL 원복 큐 |
| `common_fix.sh` | 01/03/08 `fix.sh` — `common.sh` 가 source | 자동 조치 공통: 백업·원복·감사 로그, 설정 파일 편집(F2), 비밀번호 직접 입력, 진입점 가드(F1·F6), 서비스·권한 조치, 전체 원복 |
| `Common.psm1` | Windows 계열 카테고리(02, 03의 IIS, 07, 08의 MSSQL) | 위와 동일한 기능의 PowerShell 5.1 구현 (`Write-Log`, `Get-OsFamily`, `Show-Progress`, `Save-ResultJson`, `New-ReportHtml` 등) |
| `extract_guide.py` | 분석자 PC 전용 | 가이드 PDF → 카테고리별 `guide.json`/`guide.md` 추출·정리. **이후 모든 check/fix 구현의 유일한 기준**을 만드는 선행 작업 |
| `report/head.html`, `mid.html`, `tail.html` | 진단 대상/분석자 공용 | 오프라인 단일 파일 보고서 템플릿. `cat head.html <카테고리>/guide.json mid.html result.json tail.html > report.html` 로 결합하며, 파싱은 전부 브라우저 내 JS가 수행 (Python 불필요) |
| `merge.py` | 분석자 PC 전용 (0.9.0 예정) | 다중 호스트 `result.json` 병합 → 통합 HTML/XLSX |

## 결과 JSON 생성 시 유의점
- `guide.json`은 `json.dumps(..., indent=2)`로 생성되어 문자열 값의 줄바꿈이 `\n`으로
  이스케이프되어 있다. 즉 하나의 필드는 항상 한 줄이므로, `guide_field`처럼 jq 없이도
  grep/awk 한 줄 매칭으로 안전하게 조회할 수 있다. 이 전제를 깨는 방식으로 `extract_guide.py`를
  수정하지 않는다.
- `report.html`은 `guide-data`/`result-data` 두 개의 `<script type="application/json">`을
  그대로 이어붙인 것이므로, 셸 스크립트는 JSON을 파싱할 필요가 없다 (파일 결합만 하면 됨).
