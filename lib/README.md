# lib/ — 공통 모듈

모든 카테고리(`NN_*/`)가 공유하는 코드. 카테고리 폴더에는 이 모듈들을 재사용하는
`run.*`/`fix.*`/`checks/*`/`fixes/*`만 두고, 로그·진행표시·환경감지·보고서 생성 같은
공통 기능은 여기에만 구현한다 (§코딩 규칙, 루트 `CLAUDE.md`).

| 파일 | 대상 | 역할 |
|---|---|---|
| `common.sh` | Unix 계열 카테고리(01, 03의 Unix 엔진, 08의 Unix DBMS) | 로그, 색상, 진행 표시, `uname`/`os-release` 기반 환경 감지, `guide.json` 조회(`guide_field`/`guide_list_codes`), 결과 JSON(NDJSON→최종 JSON)/CSV/`summary.txt` 생성, `report.html` 렌더링 |
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
