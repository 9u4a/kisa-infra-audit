# Changelog

이 프로젝트는 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식과
[시맨틱 버저닝](https://semver.org/lang/ko/)을 따릅니다. 1.0.0(6개 카테고리 완성) 이후는
일반적인 SemVer 관례대로 기능 추가=MINOR, 버그 수정=PATCH 로 올립니다.

## [Unreleased]

## [1.1.0] - 2026-10-07
### Added
- **01_unix: Solaris/AIX/HP-UX 전용 진단 로직 7개 항목 구현** — U-01(root 원격 접속 제한),
  U-02(비밀번호 관리정책), U-03(계정 잠금 임계값), U-04(비밀번호 파일 보호), U-06(su 기능
  제한), U-18(/etc/shadow 권한), U-67(로그 디렉터리 권한). 기존에는 이 7개 항목이 Linux 이외
  환경에서 전부 `MANUAL`로만 응답했다. 예: U-01 Solaris는 `/etc/default/login` CONSOLE=,
  AIX는 `/etc/security/user` root 스탠자의 `rlogin` 속성, HP-UX는 `/etc/securetty` 로
  "원격 터미널로 root 직접 로그인 차단" 여부를 판정. U-03 AIX는 `loginretries`가 미설정이면
  기본값 0(무제한)이라는, 가이드 원문이 아니라 AIX 공식 문서가 명시한 기본값을 근거로 판정.
- **"미검증" 투명성 메커니즘**: Solaris/AIX/HP-UX는 SPARC/POWER/PA-RISC 전용이라 x86 Docker로
  실기 검증이 불가능하다(05_network의 오프라인 설정파일 분석과 같은 종류의 제약). `lib/
  common.sh`의 `append_unverified_note`를 `01_unix/run.sh`·`fix.sh`의 디스패치 루프에 한
  번만 연결해, 이 3개 환경의 모든 판정 결과(새로 구현한 7개 항목뿐 아니라 OS_FAMILY 분기가
  없는 기존 60개 "공통 로직" 항목 포함)에 "[미검증: 문서 기준 구현...]" 안내를 자동으로
  덧붙인다. fix(조치)는 이 불확실성 위에서 실제로 파일을 바꾸는 것이라 위험이 더 크므로
  의도적으로 구현하지 않았다 — 이 3개 환경의 `fixes/U-xx.sh`는 여전히 "자동 조치 미구현"을
  반환한다.

### Fixed
- **`check_owner_perm`(lib/common.sh)이 Solaris/AIX/HP-UX에서 `stat` 실패를 거짓 VULN으로
  처리하던 문제**: GNU(`-c`)/BSD(`-f`) stat 포맷이 모두 실패하면 소유자/권한이 빈 문자열로
  남는데, 기존 로직은 이를 "기준 미충족(VULN)"으로 오판했다. 이 3개 환경에서는 애초에 `stat`을
  시도하지 않고 `ls -ldL` 파싱(신규 `_mode_str_to_octal` 헬퍼)으로 전환했고, 그래도 소유자/
  권한을 못 구하면 VULN이 아니라 `ERROR`로 보고하도록 고쳤다.
- **`check_service_disabled`(lib/common.sh)가 `pgrep` 부재 시 "비활성화(양호)"로 단정하던
  문제**: pgrep이 없는 극히 드문 환경에서 실제로 서비스가 떠 있어도 거짓 양호가 날 수 있었다.
  `ps -ef | grep -E` 폴백을 추가했고, pgrep/ps 둘 다 없을 때만 `ERROR`로 보고한다(U-34/36/39/
  41/42/43/44/52/54/58 공용 헬퍼 — 8개 항목 전부에 영향).
- **U-67의 `find -maxdepth` GNU/BSD 확장 의존성 제거**: Solaris/AIX/HP-UX 네이티브 find가
  `-maxdepth`를 지원하는지 신뢰할 수 없어(실기 검증 불가), 실패 시 조용히 빈 결과로 이어져
  거짓 양호가 될 위험이 있었다. 셸 글롭(`for f in "$dir"/*`) 기반으로 재작성해 제거했다.

## [1.0.0] - 2026-10-06
### 6개 카테고리 완성
루트 `CLAUDE.md`가 정한 6개 카테고리(UNIX/Windows/웹/네트워크/PC/DBMS, 가이드 2026판 기준
총 239항목)의 진단이 모두 구현되었고, 자동 조치도 성격에 맞는 방식으로 모두 구현되었다
(Unix/Windows/PC/Web/DBMS는 `fix.*`로 직접 적용·백업·원복, Network는 장비에 접속하지 않는다는
설계 원칙에 따라 `fix.py`로 조치 명령어 스크립트만 생성). 통합 런처(`audit.sh`/`audit.ps1`)와
다중 호스트 병합(`lib/merge.py`)까지 더해 0.1.0부터 이어온 로드맵을 완료한다. 이 버전 자체에는
기능 변경이 없다 - 0.9.4에서 수행한 저장소 전체 정적분석·실기 검증을 통과한 상태를 1.0.0으로
확정한다.

| 카테고리 | 진단 | 조치 |
|---|---|---|
| 01_unix (67항목) | Linux(rhel/debian) 중심, 그 외 환경 MANUAL 폴백 | 58/67 `fix.sh` |
| 02_windows (64항목) | Windows Server 2012 R2~2022 | `fix.ps1` |
| 03_web (26항목) | Apache/Nginx/Tomcat(sh)+IIS(PowerShell) | sh/ps1 양쪽 `fix.*` |
| 05_network (38항목) | Cisco IOS 오프라인 설정파일 분석 | `fix.py` 조치 명령어 스크립트 생성 |
| 07_pc (18항목) | Windows 10/11 | `fix.ps1` |
| 08_dbms (26항목) | MySQL/PostgreSQL/Oracle(sh)+MSSQL(PowerShell) | 20/26 `fix.*` |

## [0.9.4] - 2026-10-06
### Added
- **통합 런처 `audit.sh`(POSIX sh)/`audit.ps1`(PowerShell 5.1) 신규**: 이 호스트에 적용되는
  모든 카테고리를 한 번에 진단한다 - Unix 계열은 01_unix(항상)+03_web(엔진 자동 감지)+
  08_dbms(엔진 자동 감지, 실패 시 건너뜀), Windows 계열은 02_windows+07_pc(항상)+03_web(IIS
  자동 감지)+08_dbms(MSSQL, 연결 실패는 각 항목이 개별 오류로 정직하게 보고). 카테고리별
  run.*을 그대로 호출해 결과를 모은 뒤 통합 요약을 출력한다 - 각 카테고리의 세부 옵션(`-i`/`-g`
  등)은 지원하지 않으며, 다른 run.*과 동일하게 대상 설정을 변경하지 않는다(진단 전용).
- **`lib/merge.py` 신규**: 같은 카테고리를 여러 호스트에서 각각 진단한 result.json 여러 개를
  모아 호스트별 준수율 순위와 전사(全社) 공통 취약 항목 순위를 보여주는 병합 보고서
  (`merged.csv`/`merged_summary.txt`/`merged_report.html`)를 생성한다. 분석자 PC 전용, 대상
  시스템에는 전혀 접근하지 않고 이미 생성된 result.json만 읽는다.

### Testing
- **1.0.0 전 전체 저장소 정적분석·실기 검증 수행**(사용자 요청에 따른 단위/통합 테스트 게이트):
  - ShellCheck: 전체 `*.sh` 251개 전수 검사, ERROR 수준 1건 발견·수정(`01_unix/checks/U-38.sh`
    의 `$port[[:space:]]` 가 배열 인덱싱 문법으로 오인되는 것 - `${port}[[:space:]]`로 수정,
    이번 세션 작업과 무관한 기존 코드였음). WARNING 수준은 전부 기존부터 알려진 허용 패턴(체크/
    조치 계약 변수가 run.*/fix.*에 의해 외부에서 쓰이는 것을 ShellCheck가 알 수 없는 SC2034,
    `proc_pids_by_comm_glob`의 의도된 glob 패턴을 SC2254로 오탐).
  - PSScriptAnalyzer: 전체 `*.ps1`/`*.psm1` 212개 전수 검사, ERROR 수준 0건. 전체 파일 UTF-8
    BOM/파싱 재확인도 0건 이상 없음.
  - Python: 전체 `*.py` 77개 `ast.parse` 전수 통과.
  - **실기 통합 테스트**: `audit.sh`를 Docker(Debian 12 + nginx)에서 실행해 01_unix(67항목)+
    03_web(26항목, nginx 자동 감지)+08_dbms(엔진 미감지 시 정상적으로 건너뜀) 전체 플로우를
    오류 0건으로 확인. `audit.ps1`을 실제 Windows 11 호스트에서 실행해 02_windows(64항목)+
    07_pc(18항목)+03_web(IIS 미설치로 전체 NA)+08_dbms(로컬 MSSQL 없어 항목별 정직한 오류
    보고)까지 4개 카테고리 108항목을 스크립트 실패 0건으로 확인. 이 과정에서 01_unix/03_web의
    이번 세션 `stat -L` 변경(0.9.2 DBMS 작업 중 발견한 심볼릭 링크 버그 수정)이 일반 파일
    대상에서는 동작이 그대로임(회귀 없음)을 재확인했다.
  - `lib/merge.py`는 합성 result.json(호스트 3개)으로 호스트별 준수율 정렬, 전사 공통 취약
    항목 집계, CSV/HTML 출력까지 검증.

## [0.9.3] - 2026-10-06
### Added
- **Network(Cisco IOS) 조치 명령어 스크립트 생성 구현**: `05_network/fix.py` 신규. 다른
  카테고리의 `fix.sh`/`fix.ps1`과 달리 `--apply`/`--rollback`이 없다 — 05_network/CLAUDE.md의
  원칙("장비에 접속해 변경하지 않고 조치 명령어 스크립트만 생성") 그대로, VULN 판정 항목에 대해
  실제 적용 가능한 Cisco IOS 명령어를 모아 `remediation_<host>.txt` 한 개를 생성만 하고 장비에는
  아무것도 하지 않는다.
- `fixes/cisco_ios/N-xx.py` 32개(VULN이 나올 수 있는 모든 코드) 구현 — checks/와 동일한
  "1항목=1파일" 규칙으로 각 파일이 `generate(ctx) -> list[str]`(IOS 명령어 목록)을 제공한다.
  관리 IP 대역·로그/NTP 서버 주소처럼 설정 텍스트만으로 알 수 없는 값은 `<placeholder>`로 남기고
  "주의:" 문구로 교체 필요성을 경고한다(N-06 VTY ACL/N-08 SSH 전환처럼 placeholder를 그대로
  적용하면 원격 관리 접근이 끊길 수 있는 항목은 더 명확히 경고). N-01(enable/VTY 비밀번호)/
  N-18(SNMP Community String)은 실제 값을 알 수 없어 무작위로 새 값을 생성해 스크립트에 담는다
  (08_dbms D-01/03_web WEB-02와 동일 원칙 — deviation 필드에 기록).
- `parsers/cisco_ios.py`에 `gen_secret()`(무작위 강력한 문자열 생성), `iface_name()`(인터페이스/
  라인 블록에서 이름 추출), `snmp_community_weak()`(N-18/19/20 공유 복잡성 판정) 헬퍼 추가.

### Fixed
- **같은 SNMP community 설정 라인을 N-18/19/20 이 각자 독립적으로 재발급해 서로 덮어쓰는 버그**:
  한 라인이 세 항목 모두 VULN인 경우(기본값 문자열 + ACL 없음 + RW), 생성된 스크립트를 위에서
  아래로 순서대로 적용하면 뒤에 실행되는 항목이 앞선 항목의 변경을 모른 채 옛 값으로 다시
  재발급해 ACL이나 RO 전환이 되살려지는 문제가 있었다(생성된 스크립트를 실제로 순서대로
  적용해보는 테스트로 발견). 문자열이 약한 라인은 N-18이 ACL+RO까지 한 번에 전담하고, N-19/N-20
  은 해당 라인을 건너뛰며 "N-18에 포함됨" 안내만 출력하도록 소유권을 분리해 해결했다.
- **`fixes/cisco_ios/N-19.py`의 오프바이원 토큰 슬라이싱 버그**: ACL 판정을 위해
  `"snmp-server community <string> RW".split()[2:]`로 "snmp-server"/"community" 2개만
  건너뛴다고 썼으나 실제로는 community 문자열 자신까지 "토큰"으로 남아 ACL이 없는 가장 흔한
  취약 사례에서 "ACL이 이미 있다"고 오판해 아무 명령도 생성하지 못했다(생성된 스크립트가 항상
  비어있는 것을 보고 발견). `[3:]`로 수정.

## [0.9.2] - 2026-10-02
### Added
- **DBMS 카테고리(MySQL/PostgreSQL/Oracle/MSSQL) 자동 조치(fix) 구현**: `08_dbms/fix.sh`(sh
  3엔진, `-e` 로 엔진 지정) + `08_dbms/fix.ps1`(MSSQL) 신규. `fixes/<engine>/D-xx.{sh,ps1}`
  총 35개 구현(MySQL 7/PostgreSQL 6/Oracle 15/MSSQL 7, D-01~D-26 중 20개 코드 — D-02/04/06/13/
  20/25는 전 엔진 공통으로 여전히 manual).
- DB 상태는 파일이 아니라 SQL 실행 결과라 `lib/common.sh`에 `fix_db_queue_rollback`(원복용 SQL
  문 자체를 큐에 저장 — 01_unix 의 파일 기반 `fix_backup`과 다른 메커니즘), `lib/Common.psm1`에
  `Add-FixDbRollback`/`Restore-FixDbSqlBackup`(MSSQL) 신규 추가. `fix_rollback_item`/
  `Restore-FixItem` 양쪽에 이 SQL 큐 처리를 통합.
- fix 등급은 다른 카테고리와 동일하게 가이드 '조치 시 영향' 필드를 기계적으로 분류한 뒤 U-28과
  같은 구조의 문제가 있는 항목을 재분류했다: D-10(MySQL/PostgreSQL/Oracle은 허용 IP 목록을
  스크립트가 알 수 없어 미구현, MSSQL만 W-64/PC-15와 동일한 방식으로 방화벽 활성화 자동화),
  D-07/D-19/D-26(각각 mysqld 재시작, Oracle 정적 파라미터 재시작, PostgreSQL/Oracle 정적 파라미터
  재시작이 필요 — DB 클라이언트 연결만 영향, 이 스크립트의 OS 세션에는 영향 없어 confirm 등급에서
  재시작까지 수행하도록 구현). D-01(기본 계정 비밀번호)/D-08(MySQL 해시 알고리즘 전환)은 WEB-02와
  동일한 이유로 비밀번호를 무작위로 재설정하며 원문을 증적에 남기지 않는다.

### Fixed
- **`check_owner_perm`(lib/common.sh) 심볼릭 링크 오탐**: `stat`에 `-L`(역참조) 없이 호출해
  심볼릭 링크 자체의 겉보기 권한(항상 777)을 읽어, 실제로는 안전한 대상 파일도 거짓 VULN으로
  판정하는 버그가 있었다. Oracle Free 23ai+ 가 `listener.ora`/`sqlnet.ora`를 `oradata/dbconfig/`
  의 실제 파일에 대한 심볼릭 링크로 배치하는 실제 레이아웃에서 Docker 실기 테스트로 발견(D-14/
  D-15). 같은 패턴을 쓰던 01_unix(U-24/27/31/37/40/46)와 03_web(WEB-14)의 인라인 `stat -c`
  호출, 그리고 이번에 추가한 08_dbms 의 모든 `stat -c` 호출에도 전부 `-L`을 추가해 일괄 수정.
- **`checks/postgres/D-03.sh` 근본적으로 틀린 판정 방법**: `passwordcheck`는 SQL 함수가 없는
  순수 C 훅 모듈이라 `.control` 파일이 없고 `CREATE EXTENSION`/`pg_extension`으로는 설치도
  확인도 할 수 없다(공식 `postgres:16` 이미지에 `.so`는 있지만 `.control`이 없어 실제로
  "extension은 사용할 수 없음" 오류가 남을 Docker 실기 테스트로 확인). `shared_preload_libraries`
  GUC 로 판정하도록 수정.
- **`checks/oracle/D-15.sh` 공백 포맷 미인식**: `ADMIN_RESTRICTIONS_LISTENER = ON`(표준 listener.ora
  표기, `=`와 값 사이 공백 포함)을 `=ON`(공백 없음) 패턴만 찾는 정규식이 인식하지 못해, 정상
  설정해도 거짓 VULN이 나는 버그. `=[[:space:]]*ON` 으로 수정.
- **`fixes/mssql/D-26.ps1` 원복 순서 버그**: `SERVER AUDIT SPECIFICATION`이 참조 중인
  `SERVER AUDIT`를 먼저 `DROP`하려 해 조용히 실패, 원복이 전혀 되지 않는 문제. 참조하는
  SPECIFICATION을 먼저 비활성화·삭제한 뒤 AUDIT를 삭제하도록 순서 수정.
- **`fixes/oracle/D-03/D-05/D-09/D-22.sh` 원복 부정확**: `ALTER PROFILE ... LIMIT ... DEFAULT`
  로 원복하면 Oracle의 "내장 기본값"으로 돌아가는데, 최신 버전(23ai/26ai)의 실제 내장 기본값이
  가이드가 가정한 UNLIMITED/NULL이 아닐 수 있어 조치 이전 값을 정확히 복원하지 못하는 문제가
  있었다. 조치 전 실제 현재 값을 조회해 그 값 그대로 원복 SQL을 구성하도록 수정.

### Testing
- **Docker(MySQL 8/PostgreSQL 16/gvenzl Oracle-Free 23ai/26ai, MSSQL은 별도 PowerShell
  컨테이너에서 sqlcmd 원격 접속)에서 fix 전체 흐름 실기 검증**: dry-run → `--apply`(auto 즉시,
  confirm은 비대화형에서 안전 거부 또는 직접 호출로 로직 검증) → 재검증 → `--rollback`까지
  엔진별로 최소 1개 이상의 실제 VULN→적용→GOOD/MANUAL 경로 확인(MySQL 7/7, PostgreSQL 5/6,
  Oracle 15/15, MSSQL 3/7 직접 검증 — 나머지는 기본 이미지가 이미 GOOD 상태라 인위적 VULN
  재현이 어려워 코드 리뷰로만 확인, D-10(MSSQL 방화벽)은 Linux 컨테이너에 `Get-NetFirewallProfile`
  이 없어 Windows/PC fix와 동일한 수준(로직 검증만)).
- **재시작이 필요한 항목(D-07/D-19/D-26)은 Docker 단일 프로세스 컨테이너의 한계를 실기로 확인**:
  PostgreSQL/MySQL 공식 이미지는 DB 서버 프로세스 자체가 컨테이너 PID 1이라, `pg_ctl restart`로
  재시작하면 컨테이너 자체가 종료된다(실제 systemd 환경/VM에서는 발생하지 않는 Docker 특유의
  제약). Oracle(gvenzl 이미지)은 별도 supervisor가 PID 1이라 재시작이 컨테이너를 죽이지 않아
  D-26 Oracle은 재시작 포함 전체 경로를 실제로 끝까지 검증했다. PostgreSQL은 SPFILE/GUC 설정
  변경까지만 확인, 재시작 자체는 코드 리뷰로만 검증(U-65 NTP 서비스 기동과 같은 종류의 한계).

## [0.9.1] - 2026-09-30
### Added
- **Web 카테고리 IIS 대상 자동 조치(fix) 구현**: `03_web/fix.ps1` 신규(02_windows/fix.ps1 과
  완전히 동일한 dry-run 기반 흐름·CLI). `fixes/iis/WEB-xx.ps1` 17개 구현(WEB-03/04/05/06/07/
  08/09/10/12/13/14/16/18/19/21/22/26 — WEB-02는 IIS 진단이 절대 VULN을 반환하지 않아 제외,
  WEB-11/15/20/24/25는 guide.json에서 이미 manual).
- `lib/Common.psm1`에 IIS 전용 fix 헬퍼 추가: 경로 전체 백업 후 삭제(`Backup-FixPathAndRemove`/
  `Restore-FixPathRemoveBackup` — 01_unix `fix_backup_remove_path`의 PowerShell 버전,
  Copy-Item -Recurse로 내용을 통째로 보존), 애플리케이션 풀 identity(`Set-FixAppPoolIdentity`).
  `Set-FixWebConfigProperty`(0.8.2에서 FTP용으로 추가된 헬퍼)를 그대로 재사용해 대부분의 IIS
  설정 값 변경을 구현했다.
- WEB-09(프로세스 권한)는 LocalSystem 애플리케이션 풀을 ApplicationPoolIdentity(IIS가 풀마다
  자동 관리하는 전용 최소 권한 가상 계정)로 전환한다 — 특정 사용자 계정을 새로 만들 필요가
  없어 W-14류의 "계정 생성 필요" 문제에 해당하지 않는다. WEB-21(HTTPS 리다이렉트)은 https
  바인딩이 있는 사이트만 sslFlags에 Ssl을 추가해 평문 접근을 차단하고, 바인딩이 없는 사이트는
  인증서가 없어 안전하게 조치할 수 없으므로 건드리지 않고 오류로 안내한다(WEB-20과 동일한
  이유). WEB-13/WEB-19는 hiddenSegments/handlers 컬렉션 원소 추가·제거라 표준 webconfig
  백업/원복 대상이 아니라는 한계를 CLAUDE.md에 기록했다.

### Testing
- **실제 IIS 미설치 — 로직/구문 검증만 수행**(0.8.1/0.8.2와 동일한 이유로 사용자가 이미 확인한
  범위를 그대로 적용): `ParseFile` 파싱 오류 0건, UTF-8 BOM 보정, `Invoke-ScriptAnalyzer`
  (Error 심각도) 이슈 0건, 더미 result.json으로 `fix.ps1` dry-run 실행 경로까지 확인했다.
  `WebAdministration` cmdlet 자체의 실제 동작(Add-/Remove-WebConfigurationProperty 컬렉션
  조작 포함)은 검증하지 못했다.

## [0.9.0] - 2026-09-30
### Added
- **Web 카테고리(Apache/Nginx/Tomcat) 자동 조치(fix) 구현**: `03_web/fix.sh` 신규(01_unix/fix.sh
  와 완전히 동일한 dry-run 기반 흐름·CLI — IIS는 별도 `fix.ps1` 예정, 이번 범위 아님).
  `fixes/WEB-xx.sh` 18개 구현(WEB-01/02/03/04/06/07/08/09/12/13/14/16/18/19/21/22/23/26).
  `lib/common.sh`에 `fix_backup_remove_path`(삭제가 조치 자체인 항목 전용 - tar로 전체 내용을
  백업한 뒤 삭제, `.TARBALL.tgz` 마커를 `fix_rollback_item`이 인식해 원복 시 압축 해제로 완전
  복원) 추가.
- fix 등급은 다른 카테고리와 동일하게 가이드 '조치 시 영향' 필드를 기계적으로 분류한 뒤, U-28과
  같은 구조의 문제가 있는 3개 항목을 manual로 override: WEB-11(DocumentRoot 분리는 실제 콘텐츠
  이전이 필요해 단순 값 변경이 아님), WEB-20(SSL/TLS 활성화에는 유효한 인증서가 필요해 스크립트가
  발급할 수 없음), WEB-02는 confirm 유지(무작위 강력 비밀번호는 안전하게 생성 가능하나 기존
  운영 자동화가 의존할 수 있어 confirm). WEB-21(HTTP 리다이렉션)도 confirm으로 재분류했고,
  fix 스크립트 자체도 Apache는 ServerName 을 확보했을 때만 안전하게 리다이렉트를 추가하며,
  Nginx는 올바른 server{} 블록을 텍스트 치환만으로 특정할 수 없어 자동 조치 대상에서 제외하고
  수동 안내로 남긴다. WEB-09(프로세스 권한)는 Apache/Nginx의 무중단 graceful reload/reload가
  기존 연결을 끊지 않는다는 점에 근거해(xinetd reload와 동일한 안전성 논리) 설정 변경 직후
  함께 수행하도록 구현했다 — checks/WEB-09.sh가 /proc 기반 "실행 중" 프로세스를 직접 확인하는
  유일한 항목이라 재시작 없이는 재검증을 통과할 수 없기 때문. check가 VULN을 절대 반환하지
  않는 3개(WEB-05/10/17)는 fix 스크립트를 작성하지 않았다(U-45와 동일한 패턴).

### Fixed
- **`fix_rollback_all`(전체 원복) 순서 버그**: 여러 항목이 같은 파일을 순차 수정한 경우(예:
  WEB-04→WEB-08→WEB-16→WEB-22가 모두 같은 httpd.conf를 수정), 원복을 적용 순서(정순)대로
  처리하면 나중에 적용된 항목의 백업(이미 앞 항목의 변경이 반영된 스냅샷)이 마지막에 덮어써
  앞 항목의 조치만 원복 후에도 남아있는 버그가 있었다. `lib/common.sh`(sh)와
  `lib/Common.psm1`(PowerShell) 양쪽 모두 코드 내림차순(적용 역순)으로 처리하도록 수정 —
  이 버그는 01_unix/02_windows/07_pc에도 잠재해 있었으나(공용 함수), 여러 항목이 동일 파일을
  건드리는 경우가 그동안 우연히 없어서 발견되지 못했다. Web fix 실기 테스트(Docker, 한 config
  파일에 4개 이상의 auto 항목이 동시에 적용되는 상황)에서 처음 발견됨.
- **`checks/WEB-19.sh`(SSI 사용 제한) 실제 버그**: Apache의 "Options ... Includes" 검색에서
  WEB-04/WEB-12와 달리 `-Includes`(비활성화 표기) 를 제외하는 필터가 빠져 있어, 조치 후
  "Options -Includes" 상태도 여전히 "Includes 활성"으로 오탐(거짓 VULN)하는 버그가 있었다.
  WEB-04/WEB-12와 동일한 `grep -v '\-Includes'` 필터를 추가해 수정 — fix 스크립트를 실기
  테스트하는 과정에서 발견(진단 전용 테스트로는 이 조치-후 상태를 지나가 본 적이 없었음).
- **Tomcat Connector 다중 라인 태그에 속성을 삽입하는 sed 패턴 버그(WEB-08/WEB-16)**: 실제
  tomcat:10 기본 `server.xml`의 `<Connector ...>` 태그는 속성이 여러 줄에 걸쳐 있어, 닫는
  `>`가 같은 줄에 있다고 가정한 sed 치환이 매칭되지 않아 조용히 아무 일도 하지 않는 버그가
  있었다(재검증에서 VULN으로 남아 정상적으로 실패·원복 처리되긴 했으나 의도한 조치 자체가
  적용되지 않음). `<Connector` 토큰 바로 뒤에 속성을 삽입하는 awk 방식으로 변경해 태그가
  여러 줄에 걸쳐 있어도 안전하게 동작하도록 수정(check(WEB-16)의 판정 로직도 "Connector"와
  "server=" 가 같은 줄에 있는지로 판정하므로 이 방식이 check와도 일치함).

### Testing
- **Docker(공식 httpd:2.4/nginx:latest/tomcat:10 이미지)에서 fix.sh 전체 흐름 실기 검증**:
  세 엔진 모두에서 dry-run → `--apply --yes`(auto 즉시 적용, confirm 은 비대화형에서 안전하게
  거부) → 재검증(GOOD 전환 확인) → 개별 항목 직접 호출(confirm 항목의 실제 로직 검증) →
  `--rollback`(여러 항목이 같은 파일을 수정한 경우의 정확한 역순 복원 포함) 까지 end-to-end로
  확인. 18개 fix 스크립트 전부 최소 1개 엔진에서 실제 적용→재검증 GOOD 까지 확인했다(WEB-09
  프로세스 권한 전환만 두 이미지 모두 기본값이 이미 non-root라 VULN 상태를 인위적으로 만들지
  못해 코드 리뷰로만 검증 — 나머지는 필요 시 설정을 인위적으로 취약하게 만들어(예: Tomcat
  allowLinking=true 주입) 실제 VULN→적용→GOOD 경로를 확인함).

## [0.8.2] - 2026-09-29
### Added
- **Windows/PC 자동 조치(fix) 구현**: `02_windows/fix.ps1`, `07_pc/fix.ps1` 신규(01_unix/fix.sh
  와 동일한 CLI·흐름 — dry-run 기본, `-Apply`/`-Apply -Yes`/`-Rollback`). `lib/Common.psm1`에
  Windows 계열 전용 fix 공통 인프라 추가: `New-FixOutputDir`, `Get-ResultVulnCodes`,
  레지스트리(`Backup-/Restore-/Set-/Remove-FixRegistryValue`), 서비스(`Backup-FixServiceState`,
  `Disable-FixService`), 로컬 계정(`Set-FixLocalAccountDisabled`), NTFS ACL(`Remove-FixAclIdentity`),
  SMB 공유(`Revoke-FixShareEveryone`), IIS/FTP 서버 설정(`Set-FixWebConfigProperty`), 방화벽
  프로필(`Backup-/Restore-FixFirewallProfiles`), 보안 정책 secedit(`Set-FixSecPolicyValue`,
  `Set-FixSecPrivilege` — 값 하나 단위 원복이 불가능한 전역 상태라 실행 1회당 스냅샷 1개만
  백업하고 `--Rollback` 전체 원복에서만 재적용), 항목/전체 원복(`Restore-FixItem`,
  `Invoke-FixRollbackAll`).
- `02_windows/fixes/W-xx.ps1` 48개, `07_pc/fixes/PC-xx.ps1` 11개 구현. fix 등급(auto/confirm/
  manual)은 01_unix 와 동일하게 가이드 '조치 시 영향' 필드를 기계적으로 분류(정확히 "일반적인
  경우 영향 없음"만 auto, 그 외 confirm, 진단이 manual이면 fix도 manual)한 뒤, U-28과 같은
  구조의 문제(스크립트가 안전한 값을 스스로 결정할 수 없거나 비가역적 위험이 있는 조치)가 있는
  6개 항목을 manual로 override 했다: W-12(LSA 정책 객체라 secedit/레지스트리로 조작 불가),
  W-14(원격 접속용 "별도 계정 생성"에 계정명/비밀번호 invent 필요), W-24(허용 IP 목록 invent
  필요), W-45(백신 "설치" 자체는 자동화 불가), W-61/PC-07(FAT→NTFS 변환은 재부팅·데이터 손상
  위험이 있는 비가역적 작업), PC-08(멀티부팅 시 제거 대상 OS 판단 불가). W-64/PC-15(방화벽
  켜기)는 가이드 문구상 기계적으로는 auto 이지만 이 스크립트가 실행 중인 원격 관리 세션(RDP/
  WinRM)을 끊을 수 있는 lockout 위험이 있어 confirm 으로 재분류하고, 켜기 전 원격 데스크톱/
  원격 관리 사전정의 방화벽 규칙 그룹을 먼저 활성화하도록 구현했다(deviation 필드에 각 사유
  기록). check가 VULN을 절대 반환하지 않아 fix가 트리거될 일이 없는 8개(W-01/06/19/26/35/47,
  PC-16/17)는 U-45와 동일한 이유로 fix 스크립트를 작성하지 않았다.

### Testing
- **실제 Windows 11 호스트에 `--Apply` 실제 적용은 수행하지 않음(사용자 확인)** — 레지스트리/
  서비스/보안정책/방화벽을 실제로 바꾸는 위험 때문에, 01_unix 처럼 Docker로 안전하게 실기검증할
  방법이 마땅치 않은 Windows 스택 특성상 로직/구문 검증까지만 수행하기로 명시적으로 선택했다.
  `[System.Management.Automation.Language.Parser]::ParseFile`로 전체 62개 신규/수정 `.ps1`
  파일(`lib/Common.psm1`, 두 `fix.ps1`, `fixes/*.ps1`) 파싱 오류 0건 확인, UTF-8 BOM 누락분
  전량 보정, `Invoke-ScriptAnalyzer`(Error 심각도) 이슈 0건 확인, 더미 `result.json`으로
  `fix.ps1` dry-run 실행 경로(VULN 코드 추출 → guide.json 등급 조회 → manual/auto 분기 →
  guide.json 에 없는 미지 코드의 안전한 기본 처리)까지 실제로 실행해 확인했다. 레지스트리/
  서비스/secedit 등 cmdlet 자체의 실제 동작은 검증하지 못했다 — 02_windows·07_pc/CLAUDE.md 에
  이 한계를 명시했다.

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
