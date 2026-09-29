# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식과
[시맨틱 버저닝](https://semver.org/lang/ko/)(0.x 개발 단계)을 따릅니다.

## [Unreleased]

## [0.8.1] - 2026-09-29
### Added
- **Web 카테고리 IIS 지원 추가**: 별도 진입점 `03_web/run.ps1`(PowerShell 5.1, `-i/-g/-l/-o/-h`,
  단일 엔진이라 `-e` 없음)과 `03_web/checks/iis/WEB-xx.ps1` 23개 구현. 가이드 원문 "대상" 필드
  기준으로 IIS가 대상인 WEB-02~16, WEB-18~22, WEB-24~26 만 구현했고(WEB-01/17/23은 IIS 비대상),
  `guide.json`의 각 항목 `envs` 필드에 `"iis"`를 추가했다.
- `lib/Common.psm1`에 IIS 연동 헬퍼 추가: `Test-IisAvailable`(WebAdministration 모듈 가용성을
  프로세스당 1회만 확인해 `$Global:IisAvailableCache`에 캐시), `Get-IisSiteNames`,
  `Get-IisSitePhysicalPath`, `Get-IisConfigValue`(`Get-WebConfigurationProperty` 래퍼 — 사이트별/
  서버 전역 설정을 동일한 방식으로 조회).
- IIS 다중 사이트 판정 정책: 사이트 하나라도 VULN이면 전체 VULN, 전부 GOOD이면 GOOD, 판정
  불가/규칙 존재만으로 확정 못 하는 경우(WEB-21 URL Rewrite 등)는 MANUAL — 기존 Unix 계열
  Web(Apache/Nginx/Tomcat) 다중 엔진 집계 정책(03_web/CLAUDE.md)과 동일한 원칙을 사이트 단위로
  적용했다.
- WEB-02(관리자 비밀번호)·WEB-24(업로드 경로)는 IIS에 표준화된 설정 키가 없어 항상 MANUAL,
  WEB-25(패치 관리)는 다른 엔진과 동일하게 조직 정책 판단이 필요해 항상 MANUAL로 응답한다
  (버전 정보만 증적 제공).

### Testing
- **실제 IIS 미설치 — 로직/구문 검증만 수행**(사용자 확인 후 결정, 실제 Windows 11 호스트에
  IIS 기능을 설치하지 않음): `[System.Management.Automation.Language.Parser]::ParseFile`로 전체
  25개 신규/수정 `.ps1` 파일(`lib/Common.psm1`, `03_web/run.ps1`, `checks/iis/*.ps1`) 파싱 오류
  0건 확인, UTF-8 BOM 누락분 전량 보정, `Invoke-ScriptAnalyzer`(Error/Warning) 실행 결과 새 IIS
  체크 파일에서는 경고 0건(기존 파일의 `Write-Host`/`Global` 변수 경고는 프로젝트 기존 관례). 단,
  대상 호스트에 실제 IIS가 없어 `WebAdministration`/`Get-WebConfigurationProperty` 등 cmdlet의
  실제 동작은 검증하지 못했다.

## [0.8.0] - 2026-09-29
### Added
- **자동 조치(fix) 공통 인프라** — 진단(`run.*`)과 완전히 분리된 `fix.*` 진입점을 처음 도입.
  `lib/common.sh`: `result_list_vuln_codes`(result.json에서 VULN 코드만 추출), `fix_prepare_dir`
  (백업/로그 디렉터리 준비), `fix_backup`/`fix_rollback_item`/`fix_rollback_all`(파일·디렉터리
  백업 및 원복 — 디렉터리는 메타데이터만, 신규 생성 파일은 WAS_ABSENT 마커로 추적), 재사용
  헬퍼 `fix_set_owner_perm`(check_owner_perm과 짝), `fix_service_disable`/`fix_xinetd_disable`
  (check_service_disabled과 짝, xinetd는 reload까지 수행).
- `01_unix/fix.sh`: `-r <result.json>` 로 진단 결과를 읽어 VULN 항목만 대상으로 하며, 기본은
  dry-run이다. `--apply`로 실제 적용, `--apply --yes`는 auto 등급만 자동 적용하고 confirm
  등급은 항상 개별 y/N 확인(비대화형 환경에서는 안전하게 자동 거부), `--rollback <dir>`로
  백업에서 원복. 적용 직후 해당 check를 재실행해 VULN/ERROR 를 벗어났는지 재검증하고, 실패 시
  자동 원복한다.
- `01_unix/fixes/U-01.sh` ~ `U-67.sh` 중 58개 구현(가이드 원문 '조치 방법'/'점검 및 조치 사례'
  그대로 적용). 조치 등급(`fix` 필드: auto/confirm/manual)은 가이드 원문의 '조치 시 영향' 필드를
  근거로 기계적으로 분류했다 — "일반적인 경우 영향 없음"이면 auto, 그 외 어떤 단서라도 있으면
  confirm, 진단 자체가 MANUAL인 항목은 fix도 manual. U-28(접속 IP 제한)은 예외적으로 confirm이
  아닌 manual로 재분류했다(관리자가 허용 IP를 직접 정해야 하며, 잘못 자동 적용 시 관리 세션까지
  포함한 전체 원격 접속 lockout 위험이 있어 안전한 자동 조치가 원천적으로 불가능함 — `deviation`
  필드에 근거 기록). U-45(메일 버전 점검)는 check가 VULN을 전혀 내지 않는 설계라 fix 스크립트가
  트리거될 일이 없어 작성하지 않음.
- **Docker 컨테이너(rockylinux:9)에서 fix.sh 전체 흐름(dry-run→적용→재검증→원복) 실기 검증**:
  실제 진단으로 얻은 VULN 12건에 대해 dry-run, `--apply --yes` 실제 적용(파일 기반 auto 항목
  4건 전부 재검증 양호 확인), `--rollback` 으로 원본 상태 완전 복원(파일 내용·권한·신규 생성
  파일 삭제 모두 확인)까지 end-to-end로 검증. systemd 가 PID 1 이 아닌 컨테이너 특성상
  `systemctl`기반 서비스 시작/비활성화 조치(예: U-65 NTP)는 스크립트가 "실패를 정직하게
  ERROR로 보고하고 원복"하는 것까지는 확인했으나 실제 서비스 기동 성공까지는 검증하지 못함
  (실제 systemd 환경에서는 정상 동작 — 컨테이너 테스트 환경의 한계로 명시).

### Fixed
- **U-31(홈 디렉토리)/U-24(환경변수 파일) 실제 버그**: `sync`/`shutdown`/`halt` 처럼 쉘 필드에
  실행 유틸리티 경로(`/bin/sync` 등)를 쓰고 홈 디렉터리를 `/sbin`(여러 계정이 공유하는 시스템
  디렉터리)으로 지정하는 표준 관례적 계정을, "로그인 가능한 일반 계정"으로 잘못 분류해 홈
  디렉터리 소유자를 해당 계정으로 바꾸려 시도하는 버그를 Docker 실기 테스트로 발견 — 실제로
  적용됐다면 `/usr/sbin`(시스템 바이너리 디렉터리)의 소유자가 바뀌는 심각한 손상으로 이어질
  뻔했다(다행히 이 테스트 환경에서는 chown이 조용히 실패해 실제 손상은 없었음). 홈이 공유
  시스템 디렉터리(`/sbin`, `/usr/sbin`, `/bin`, `/usr/bin`, `/`)인 계정은 대상에서 제외하도록
  checks/fixes 양쪽 모두 수정. **거의 모든 Linux 시스템에 sync/shutdown/halt 계정이 표준으로
  존재하므로, 이 버그는 v0.2.0부터 존재해온 U-31/U-24의 실제 오탐(false VULN) 원인이었다.**
- **fix.sh 의 confirm 확인 프롬프트가 비대화형 환경에서 크래시**: `/dev/tty` 가 파일로는
  "존재"해도(`-r` 테스트 통과) 제어 터미널이 없는 실행 환경(`docker exec`, cron 등)에서는 실제
  읽기 시도 시 "No such device or address" 로 실패하는데, 이때 `set -u` 환경에서 변수가 아예
  할당되지 않아 "unbound variable" 로 스크립트 전체가 죽는 버그를 Docker 실기 테스트로 발견.
  읽기 실패를 명시적으로 흡수하고 항상 안전한 기본값(미확인=거부)으로 폴백하도록 수정.
- **재검증 성공 기준이 너무 엄격함**: U-66처럼 판정 기준 자체가 조직 정책 대조를 요구해
  아무리 올바르게 조치해도 check가 `MANUAL` 까지만 반환하고 절대 `GOOD` 에 도달할 수 없는
  항목이 있는데, 재검증 성공 조건을 `CHECK_STATUS = GOOD` 으로만 판정해 이런 항목은 항상
  "실패"로 오판해 불필요하게 원복되는 문제를 발견. 성공 기준을 "VULN/ERROR 를 벗어났는가"로
  완화(GOOD/MANUAL/NA 모두 성공으로 인정)하도록 수정.

## [0.7.0] - 2026-09-28
### Added
- `05_network` 네트워크 장비 38개 항목(N-01~N-38) 중 Cisco IOS 진단 로직 구현, Python 3.10+
  (`05_network/run.py` + `checks/cisco_ios/N-xx.py`). 다른 카테고리와 달리 대상 장비에 아무것도
  배치하지 않는 **오프라인 설정파일 분석** 방식이다 — 미리 수집한 `show running-config` 텍스트
  파일을 입력받아 분석자 PC에서 판정한다(05_network/CLAUDE.md).
- `05_network/parsers/cisco_ios.py`: 설정 텍스트 파싱 컨텍스트(`Ctx`) — 전체 텍스트 정규식 검색,
  `line con/vty/aux` 및 `interface` 블록 추출(Cisco IOS의 "하위 명령은 공백 1칸 들여쓰기" 규칙으로
  블록 경계 판별), IP가 설정되고 shutdown되지 않은 "사용 중" 인터페이스만 골라내는 헬퍼 포함.
- `lib/report_common.py`: 분석자 PC Python 카테고리용 공용 결과/보고서 모듈 — sh의
  `lib/common.sh`, PowerShell의 `lib/Common.psm1`과 동일한 역할(result.json 조립, CSV/summary
  작성, report.html 렌더링)을 Python으로 제공. 향후 Python 기반 카테고리(다중 호스트 병합 등)가
  재사용할 공용 인프라.
- 실행: `python run.py -f running-config.txt` (벤더 자동 판별), `-v cisco_ios`(수동 지정),
  `-d configs/`(디렉터리 일괄), 그 외 `-i/-g/-l/-o/-h` 는 전 카테고리와 동일.
- **실기 검증**: 실제 장비가 없어(카테고리 특성상 Docker화 불가능) 직접 작성한 Cisco IOS
  `show running-config` 픽스처 2종(전형적 취약 설정/전형적 강화 설정, 실제 IOS 문법 기준)으로
  38개 항목 전체를 교차 검증 — 취약 픽스처: 취약 30·수동점검 6·양호 2·오류 0, 강화 픽스처:
  양호 30·수동점검 8·취약 0·오류 0(동일 8개 항목이 두 픽스처 모두에서 일관되게 MANUAL로 귀결됨을
  확인, 설계대로 조직 정책 판단이 불가피한 항목들). Windows 콘솔 인코딩 문제(cp949) 방지를 위해
  `sys.stdout.reconfigure(encoding="utf-8")` 적용.

### Fixed
- **SNMP community ACL/권한 판정(N-19/N-20) 정규식이 다음 줄까지 캡처하는 버그**: Cisco 설정의
  섹션 구분자 `!`는 별도 줄에 있는데, 정규식의 선택적 "ACL 인자" 그룹에 `\s+\S+`(개행 포함)를
  써서 다음 줄의 `!`를 ACL 인자로 잘못 캡처해 "ACL이 지정됨=양호"로 오판하던 버그를 픽스처
  테스트로 발견. 줄 내부 공백만 매치하는 `[ \t]+`로 교체해 줄 경계를 넘지 않도록 수정.
- SNMP Community String 등 비밀번호에 준하는 값은 증적(evidence)에 원문을 남기지 않고
  길이/기본값 여부만 남기도록 처리(08_dbms의 "접속정보 원문 미저장" 원칙을 이 카테고리에도 적용).

### Note
- 가이드 원문이 명시적으로 "기본값이 비활성화"라고 밝힌 항목(N-35 identd, N-38 mask-reply)은
  그 기본값을 신뢰해 설정에 명시적 비활성화 라인이 없어도 양호로 판정한다. 그 외 기본값이
  버전에 따라 다를 수 있는 항목(N-26 finger, N-28 small-servers, N-31 directed-broadcast)은
  임의로 안전하다고 가정하지 않고 MANUAL로 응답한다(W-48 레지스트리 기본값 오판 사례와 동일 원칙).
- Juniper/Alteon/Passport/Piolink 는 미구현 — 이후 로드맵 과제.

## [0.6.1] - 2026-09-28
### Added
- `08_dbms` DBMS 26개 항목에 Oracle(22항목, `checks/oracle/D-xx.sh`)과 MSSQL(14항목,
  `checks/mssql/D-xx.ps1` + 신규 `08_dbms/run.ps1`)을 추가 — DBMS 4대 엔진(MySQL/PostgreSQL/
  Oracle/MSSQL) 우선 구현이 완료됨.
- `lib/common.sh`: Oracle 연결/쿼리 헬퍼(`oracle_query`, `oracle_home`, `oracle_sqlnet_ora`,
  `oracle_listener_ora`), 부분 일치 프로세스 조회(`proc_pids_by_comm_glob`, Oracle
  `ora_pmon_<SID>`처럼 이름에 SID가 섞인 프로세스용). 비밀번호는 sqlplus 인자로 넘기지 않고
  접속 문자열을 표준입력(파이프)으로만 전달한다.
- `lib/Common.psm1`: MSSQL 연결/쿼리 헬퍼 `Invoke-MssqlQuery`(sqlcmd 기반, `-C` 로 자체 서명
  인증서 신뢰). 비밀번호는 `SQLCMDPASSWORD` 환경변수로만 전달.
- `08_dbms/run.ps1`: 다른 카테고리와 동일한 CLI(`-l/-i/-g/-o/-h`) + MSSQL 전용 접속 옵션
  (`-SqlHost/-SqlPort/-SqlUser/-SqlDb`). MSSQL은 단일 엔진이라 `-e` 는 생략.
- **Oracle: Docker 컨테이너(gvenzl/oracle-free 23ai/26ai 비공식 이미지)에서 실제 진단 실행으로
  검증**, 오류 0건. **MSSQL: 공식 Linux 이미지(mcr.microsoft.com/mssql/server:2022-latest) +
  PowerShell 컨테이너(mcr.microsoft.com/powershell, mssql-tools18 apt 설치)로 원격 접속 검증**,
  DB 쿼리 기반 항목 오류 0건 — D-10(Windows 방화벽 조회)만 Linux 컨테이너에서 테스트 불가능해
  실제 Windows 11 호스트에서 별도로 로직 검증함(D-13 ODBC 조회도 동일).

### Fixed
- **Oracle 내장 롤 대량 오탐(D-11/D-20/D-21)**: 가이드 원문이 제시한 예외 목록은 특정 시점(구버전)
  Oracle의 내장 롤을 정적으로 나열한 것이라, 19c/21c/23c 이후 추가된 수십 개의 신규 내장 롤
  (GSMADMIN_INTERNAL, XDB, AUDIT_ADMIN 등)을 "인가되지 않은 일반 사용자"로 오판하는 버그를
  Docker(gvenzl/oracle-free) 실기 테스트로 발견. `dba_users.oracle_maintained='N'` 조건으로
  대체해 Oracle 버전에 관계없이 동작하도록 수정.
- **PowerShell `$Script:` 스코프가 파일 경계를 넘지 않는 버그**: `run.ps1`에서 설정한
  `$Script:DbErrFile`을 `lib/Common.psm1`(모듈 스코프)과 `checks/mssql/*.ps1`(각 체크 파일
  스코프)이 서로 다른 변수로 인식해, DB 연결 실패 시 실제 오류 메시지 대신 항상 빈 문자열만
  표시되던 버그를 발견. `$Global:` 스코프로 전환해 수정(PowerShell 5.1/7 공통 이슈로, 여러
  스크립트 파일에 걸쳐 상태를 공유해야 하는 모든 향후 카테고리에 적용되는 교훈).
- **MSSQL `USE master;` 결과 오염(D-11/D-23/D-24)**: `sqlcmd`가 `USE` 실행 시 "Changed database
  context to 'master'." 안내 메시지를 결과 스트림에 섞어 출력해, 실제 조회 결과가 0건이어도
  항상 "결과 있음(취약)"으로 오판되던 버그를 Docker 실기 테스트로 발견. `master.sys.*` 3-part
  naming으로 `USE` 없이 조회하도록 수정.
- **MSSQL 기본 제공 호환 테이블 오탐(D-11)**: `spt_fallback_db`/`spt_values`/`spt_monitor` 등은
  Microsoft가 기본으로 PUBLIC에 SELECT를 부여해 배포하는 레거시 호환용 테이블이라 오탐 대상에서
  제외.
- **`$env:TEMP`가 Linux(pwsh 7)에서 비어 있는 문제**: MSSQL이 Linux 호스트에서도 동작할 수 있어
  `08_dbms/run.ps1`이 Windows 전용 `$env:TEMP` 대신 `[System.IO.Path]::GetTempPath()`(양쪽
  플랫폼 동작)를 쓰도록 수정.

## [0.6.0] - 2026-09-28
### Added
- `08_dbms` DBMS 26개 항목(D-01~D-26) 중 MySQL/PostgreSQL 대상 진단 로직 구현, POSIX sh —
  각 엔진의 카탈로그/뷰가 완전히 달라 `checks/mysql/D-xx.sh` / `checks/postgres/D-xx.sh` 로
  엔진별 디렉터리를 분리해 구현(08_dbms/CLAUDE.md 설계 그대로 적용). 가이드 원문의 "대상" 필드에
  해당 엔진이 없는 항목(D-05/09/12/13/15~19/22~24 등, Oracle/MSSQL/Windows OS 전용)은 두 엔진
  모두에서 `NA`로 정직하게 응답한다. Oracle/MSSQL/Altibase/Tibero/Cubrid 는 이번 버전 범위
  밖이며(로드맵 0.6.x 별도 버전), 해당 엔진 선택 시 전 항목 `NA`로 응답한다.
- `08_dbms/run.sh`: 다른 카테고리와 동일한 CLI(`-l/-i/-g/-e/-o/-h`) + DBMS 전용 접속 옵션
  (`--host/--port/--user/--db/--socket`). **비밀번호는 CLI 인자로 절대 받지 않고 `DB_PASSWORD`
  환경변수로만 전달**하며, 내부적으로 `MYSQL_PWD`/`PGPASSWORD` 환경변수로 클라이언트에 넘겨
  `ps` 목록에 노출되지 않도록 한다(08_dbms/CLAUDE.md "접속정보 취급" 원칙). `-e` 미지정 시
  `/proc` 기반으로 로컬에 구동 중인 엔진을 자동 탐지하되, 여러 엔진이 동시에 감지되면(Web과 달리
  DBMS는 엔진별 카탈로그가 완전히 달라 합산 진단이 부적절) `-e` 로 명시적으로 선택하도록 안내한다.
- `lib/common.sh`: `detect_dbms_engine`, MySQL/PostgreSQL 연결·쿼리 헬퍼(`mysql_query`,
  `psql_query`, `mysql_config_path`, `postgres_config_path`, `postgres_hba_path`) 추가.
- **Docker 컨테이너(공식 mysql:8, postgres:16 이미지)에서 실제 진단 실행으로 검증** — 두 엔진
  모두 오류 0건, 판정 결과가 컨테이너의 실제 상태(mysqld/postgres 프로세스 실행 계정, 설정 파일
  권한, mysql.user/pg_hba.conf 내용 등)와 정확히 일치함을 `/proc`·`stat`·직접 SQL 조회로 교차
  검증. 항목별 자동화 수준(auto/partial/manual)은 `guide.json` 의 `automation`/`envs` 필드에
  반영했다(재추출 시에도 `load_existing_tracking` 이 보존함을 재확인).

### Fixed
- **JSON 제어문자 오염**: `mysql -B`/`psql -A` 배치 출력은 컬럼을 TAB(0x09)으로 구분하는데,
  `lib/common.sh` 의 `json_escape` 가 TAB/CR 같은 제어문자를 이스케이프하지 않아 DBMS 증적
  (evidence)이 포함된 `result.json` 이 깨지는 버그(Python `json.loads` 가 "Invalid control
  character" 로 거부)를 Docker 컨테이너 검증 중 발견. 이스케이프 전에 TAB/CR 을 공백으로 정리하도록
  수정 — 프로젝트 전체(다른 카테고리 포함)에 적용되는 공통 함수라 향후 유사 버그를 원천 차단.
- **PostgreSQL 내장 role 오탐(D-11)**: `pg_catalog` 권한 조회 시 PostgreSQL이 기본 제공하는
  predefined role(`pg_read_all_stats` 등, `pg_` 접두사)을 "인가되지 않은 일반 사용자"로 오판하던
  버그를 Docker 실기 테스트로 발견, `grantee NOT LIKE 'pg\_%'` 조건 추가로 수정.

### Note
- 목표: 0.6.x 에서 Oracle(sqlplus)/MSSQL(sqlcmd, `run.ps1`)을 추가할 예정 — Oracle은 비공식
  Docker 이미지, MSSQL은 공식 Linux 이미지로 실기 검증 가능하나 현재 범위 밖으로 명시적으로
  분리함(사용자 확인 후 결정).

## [0.5.0] - 2026-09-28
### Added
- `03_web` 웹 서비스 26개 항목(WEB-01~WEB-26) 진단 로직 구현, POSIX sh — Apache/Nginx/Tomcat
  대상(IIS/JEUS/WebtoB는 이후 로드맵). 여러 엔진이 한 호스트에 동시에 설치되어 있어도
  `detect_web_engines` 가 전부 감지해 각각 개별 판정 후 종합한다.
- `03_web/run.sh`: 다른 카테고리와 동일한 CLI(`-l/-i/-g/-e/-o/-h`), `-e` 로 엔진 수동 지정 가능.
- `lib/common.sh`: 웹 엔진 자동 탐지/설정 경로 탐색 헬퍼(`detect_web_engines`,
  `apache_conf_path`, `nginx_conf_path`, `tomcat_home`), `Include`/`include` 체인을 재귀적으로
  따라가 실제 로드되는 설정 파일만 반환하는 `apache_extra_confs`/`nginx_extra_confs`, XML 주석을
  제거하는 `strip_xml_comments`, `ps`/`pgrep` 없이도 동작하는 `/proc` 기반 프로세스 조회
  (`proc_pids_by_comm`, `proc_uid`) 추가.
- **Docker 컨테이너(공식 httpd:2.4/nginx:latest/tomcat:10 이미지)에서 실제 진단 실행으로 검증**
  — 세 엔진 모두 오류 0건, 판정 결과가 각 이미지의 실제 기본 설정과 정확히 일치함을 확인
  (예: Apache 기본 디렉터리 리스팅 활성화 VULN, Nginx worker 프로세스 기본 비루트 권한 GOOD 등).

### Fixed
- **설정 파일 존재 ≠ 설정 적용**: Apache 공식 이미지의 `conf/extra/*.conf` 샘플들이 메인 설정에서
  주석 처리되어 실제로는 로드되지 않는데도 디렉터리를 통째로 grep 해 활성 설정으로 오판하던
  버그(WEB-18, WebDAV 오탐)를 `Include` 체인 재귀 추적 방식으로 수정.
- **XML 주석 미인식**: Tomcat `tomcat-users.xml` 의 기본 예시 관리자 계정이 `<!-- -->` 주석으로
  감싸져 있는데도 활성 계정으로 오판하던 버그(WEB-01)를 `strip_xml_comments` 도입으로 수정하고,
  동일 문제가 있던 WEB-02/04/06/10/12/13/15/16/19/22/23 의 Tomcat 분기에도 일괄 적용.
- **`ps`/`pgrep` 부재 시 무검증을 GOOD으로 오판**: 공식 Apache/Nginx Docker 이미지에 procps가
  없어 프로세스를 찾지 못했는데도 "위반 없음=GOOD"으로 판정하던 버그(WEB-09)를 `/proc` 직접
  파싱 방식으로 교체하고, 여전히 프로세스를 찾지 못하면 `MANUAL`로 정직하게 응답하도록 수정.
- **guide.json CRLF 오염**: Windows에서 Python 기본 텍스트 모드로 `guide.json`/`guide.md` 를 쓰면
  `\n` 이 `\r\n` 으로 바뀌어, 이 파일을 대상 호스트의 POSIX sh/awk(특히 mawk)로 파싱할 때 각 줄
  끝에 숨은 `\r` 때문에 필드 값이 깨지는 문제를 Docker 컨테이너 테스트로 발견. `lib/extract_guide.py`
  의 파일 쓰기에 `newline="\n"` 을 명시해 근본 수정 — 6개 카테고리 guide.json/guide.md 전체 재생성.

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
