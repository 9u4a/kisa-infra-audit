# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식과
[시맨틱 버저닝](https://semver.org/lang/ko/)(0.x 개발 단계)을 따릅니다.

## [Unreleased]

## [0.4.0] - 2026-09-28
### Added
- `07_pc` PC(Windows 10/11) 18개 항목(PC-01~PC-18) 진단 로직 전체 구현, PowerShell 5.1.
  `02_windows`와 상당수 로직 패턴을 공유(계정/암호 정책, 공유 폴더, 서비스, 방화벽, 화면보호기,
  자동 로그인 등)하되 워크스테이션 전용 항목(멀티 부팅, 상용 메신저, 이동식 미디어 자동 실행,
  원격 지원)은 새로 구현.
- `07_pc/run.ps1`: 처음부터 `-l/-i/-g/-o/-h` 통일 옵션 체계로 작성(리팩터링 없이 바로 적용).
- 이 세션의 실제 Windows 11 호스트에서 18개 항목 전체 스모크 테스트 통과, 오류 0건 — PC-04(기본
  공유 ADMIN$/C$ 실존), PC-06(실행 중인 카카오톡 프로세스) 등 실제 상태와 정확히 일치 확인.
- PC-09/10/11: 레거시 IE 전용 설정, 패치 관리 절차, EOL 여부처럼 자동 판정이 불가능한 항목은
  근거 자료만 제공하는 MANUAL로 구현.

### Fixed
- PC-15(방화벽): 작성 과정에서 넣은 방어적 `-ne $null` 가드가 "모든 프로필 정상 활성화"인 정상
  케이스를 오히려 VULN으로 오판하는 버그를 실제 호스트 테스트로 발견·수정. PowerShell에서
  `Where-Object`가 매치 없이 `$null`을 반환해도 `$null.Count`는 안전하게 `0`을 반환한다는 점을
  확인했고, 불필요한 `-ne $null` 방어 가드를 걷어냄.

### Changed
- 루트 `CLAUDE.md`에 "CLI 옵션 문자 통일" 규칙 신설: 모든 카테고리의 `run.*`/`fix.*`가 언어에
  관계없이 동일한 옵션 문자(`-l/-i/-g/-e/-o/-h`)를 쓰도록 명시.
- `02_windows/run.ps1`: 서술형 매개변수(`-Items`/`-Group`/`-ListOnly`/`-OutBase`)에
  PowerShell `[Alias]`로 `-i/-g/-l/-o` 단축 옵션 추가, `-h`(도움말) 신규 추가 — `01_unix/run.sh`와
  동일한 문자 체계로 통일.

## [0.3.0] - 2026-09-28
### Added
- `02_windows` Windows 서버 64개 항목(W-01~W-64) 진단 로직 전체 구현, PowerShell 5.1.
  실제 Windows 11 호스트(관리자 권한)에서 전 항목 스모크 테스트 완료 — 오류 0건, 각 판정이
  실제 로컬 정책/레지스트리/서비스 상태와 일치함을 확인.
- `lib/Common.psm1`: secedit 기반 로컬 보안 정책 조회 헬퍼 추가 —
  `Get-SecEditExport`(1회 캐시), `Get-SecPolicyValue`([System Access] 등),
  `Get-SecPrivilegeAccounts`(사용자 권한 할당의 SID를 계정명으로 변환), `ConvertFrom-Sid`,
  `Test-RegistryValue`(부재 시 예외 없이 `$null`).
- `02_windows/run.ps1`: `01_unix/run.sh` 와 동일한 CLI(`-Items`, `-Group`, `-ListOnly`,
  `-OutBase`) 및 출력 구조(result.json/csv, report.html, summary.txt, run.log).
- W-03/06/27/37/38/47/62: 계정 필요성·패치 정책·시작 프로그램 등 조직 판단이 필요한 항목은
  근거 자료(활성 계정, 빌드 정보, 예약 작업 목록 등)를 수집해 정직하게 `MANUAL`/`partial`
  로 응답하도록 구현 (U-07 등과 동일한 원칙).

### Fixed
- **PowerShell BOM 이슈**: Windows PowerShell 5.1이 BOM 없는 `.ps1`/`.psm1`을 시스템
  코드페이지(cp949)로 읽어 한글이 깨지며 파싱 오류(`The string is missing the terminator`)가
  발생하는 문제를 `lib/Common.psm1`에서 발견. 모든 PowerShell 파일을 UTF-8 BOM으로 재저장하고,
  루트 CLAUDE.md 코딩 규칙에 필수 절차로 명시.
- `lib/common.sh`, `lib/Common.psm1` 의 `TOOL_VERSION`이 `0.1.0`으로 하드코딩되어 실제
  `VERSION` 파일과 어긋나던 문제 수정 — 이제 두 언어 모두 `VERSION` 파일을 단일 소스로 읽음.
- W-40(감사 정책): `auditpol` 하위 범주 이름이 로캘에 따라 깨지는 문제를 로캘 독립적인
  GUID + CSV(`/r`) 조회 방식으로 교체. 배열 인덱싱 버그(빈 줄 포함 시 컬럼 오프셋이 밀리는
  문제)도 함께 수정.
- W-48(로그온하지 않고 시스템 종료 허용): 레지스트리 값이 없을 때 안전한 기본값으로 잘못
  가정했던 버그 수정 — 실제 Windows 기본값은 "사용"(취약)이므로 미설정을 양호로 오판하지
  않도록 로직 수정 (다른 레지스트리 기반 항목들도 실제 호스트 값으로 기본값을 교차 검증함).

## [0.2.0] - 2026-09-28
### Added
- `01_unix` Unix 서버 67개 항목(U-01~U-67) 진단 로직 전체 구현 (Linux rhel/debian 대상).
  Solaris/AIX/HP-UX 및 조직 정책 판단이 필요한 항목(U-07/08/23/25/33/49/64)은 근거 자료를
  수집해 `MANUAL`로 응답 (완전 자동 판정이 불가능함을 명시).
- `lib/common.sh`: `check_owner_perm`(소유자/권한 공통 판정), `check_service_disabled`
  (서비스 비활성화 공통 판정) 헬퍼 추가로 항목 간 중복 로직 제거.
- `lib/extract_guide.py`: 재추출 시 기존 `guide.json`의 구현 진행 상태(`automation`/`fix`/
  `envs`/`deviation`)를 보존하도록 병합 로직 추가 (`load_existing_tracking`). guide.json은
  여전히 수작업으로 고치지 않고 추출기 재실행으로만 갱신한다는 원칙을 지키면서, 구현 상태
  추적이 재추출로 사라지지 않도록 함.

### Verified
- 67개 항목 전체 `run.sh` 실행 스모크 테스트 통과 (결과 JSON/CSV/HTML 정상 생성, 코드 중복 없음).

## [0.1.0] - 2026-09-28
### Added
- 프로젝트 골격: 루트 `CLAUDE.md` + 6개 카테고리(`01_unix`, `02_windows`, `03_web`,
  `05_network`, `07_pc`, `08_dbms`) `CLAUDE.md`
- `lib/extract_guide.py`: 가이드 PDF(2026판)에서 카테고리별 `guide.json`/`guide.md`를
  추출하는 스크립트. 6개 카테고리 전체 항목 수 검증 완료
  (Unix 67 / Windows 64 / Web 26 / Network 38 / PC 18 / DBMS 26)
- `lib/common.sh`, `lib/Common.psm1`: 진단 공용 모듈 (로그, 진행 표시, 환경 감지,
  결과 JSON/CSV/요약 생성, 보고서 렌더링)
- `lib/report/{head,mid,tail}.html`: 단일 파일 오프라인 진단 보고서 템플릿
- `01_unix/run.sh` + `checks/U-01~U-05.sh`: Unix 진단 PoC (Linux rhel/debian 대상)
- 버전/커밋 정책: SemVer 0.x, Conventional Commits, Claude 세션 정보 비노출
  (`.claude/settings.json`, `.githooks/commit-msg`)

### Changed
- `.claude/`, 모든 `CLAUDE.md`(루트·카테고리), `.githooks/`를 저장소에서 제외(`.gitignore`).
  로컬 디스크에는 그대로 유지되며 작업 규칙 문서·커밋 훅으로 계속 사용하지만, 공개 저장소에는
  포함하지 않는다.

### Notes
- 나머지 항목(Windows/Web/Network/PC/DBMS 전체)은 로드맵(README 참고)에 따라 후속
  버전에서 구현 예정이며, 현재는 `guide.json`/`guide.md`만 준비되어 있음
