# kisa-infra-audit

주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드(2026판)를 기준으로,
Unix/Windows/Web/Network/PC/DBMS 6개 카테고리를 자동 진단하고 보고서를 생성하는 도구입니다.
가능한 항목은 자동 조치(fix)까지 지원합니다.

> ✅ v1.4.1 — Unix(67항목, Linux 대상 + Solaris/AIX/HP-UX 일부), Windows Server(64항목),
> Web(26항목, Apache/Nginx/Tomcat/IIS), PC(18항목, Windows 10/11), DBMS(26항목, MySQL/
> PostgreSQL/Oracle/MSSQL), Network(38항목, Cisco IOS) 6개 카테고리 진단 + 자동 조치
> (Network는 조치 명령어 스크립트 생성)가 구현되어 있습니다. **1.2.0부터 새 환경/벤더
> 확장은 중단하고, 이미 구현된 대상에 대한 GitHub Actions CI 기반 회귀 테스트·유지보수에
> 집중합니다.**
>
> ⚠️ 운영 서버에 쓰기 전에 [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md)(알려진 문제·미검증 범위·검증 환경 한계)를 확인하세요.
> 진단은 root/관리자 권한으로 실행해야 합니다 - 권한이 없으면 확인하지 못한 항목은 양호가 아니라 ERROR 로 표시됩니다.

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
| [`01_unix`](./01_unix) | U | 1. UNIX 서버 | 67 | 🟢 67/67 진단(Linux 전체 + Solaris/AIX/HP-UX 7항목, 미검증) + 58/67 조치(Linux) |
| [`02_windows`](./02_windows) | W | 2. Windows 서버 | 64 | 🟢 64/64 진단 + 48/64 조치(fix) 구현 |
| [`03_web`](./03_web) | WEB | 3. 웹 서비스 | 26 | 🟢 Apache/Nginx/Tomcat 26/26 진단 + 18/26 조치(fix), IIS 23/26 진단 + 17/26 조치 |
| [`05_network`](./05_network) | N | 5. 네트워크 장비 | 38 | 🟢 Cisco IOS 38/38 진단 + 조치 명령어 생성 구현 |
| [`07_pc`](./07_pc) | PC | 7. PC | 18 | 🟢 18/18 진단 + 11/18 조치(fix) 구현 |
| [`08_dbms`](./08_dbms) | D | 8. DBMS | 26 | 🟢 MySQL/PostgreSQL/Oracle/MSSQL 진단 + 조치(fix) 구현 |

## 검증된 실행 환경 (v1.4.1)
아래 환경에서는 진단·조치가 정상 동작함을 GitHub Actions CI로 확인했습니다
(최종 확인 2026-11-02: run `41369631338` 에서 Oracle 을 포함한 전 job 성공).

**확인 방법**:
- 각 항목을 가이드 판단기준의 **취약 상태와 양호 상태로 각각 세팅**하고, 진단 결과가 VULN/GOOD 으로 나오는지 확인했습니다.
- 조치(fix)가 있는 항목은 취약 상태에서 다음 순서로 확인했습니다: 적용 → 재진단 GOOD → 원복 → 원래 상태와 동일.
- 진단 전후로 시스템 상태가 같은지, 비밀값이 저장되지 않는지도 함께 검사합니다.
- 전체 커버리지는 `python3 lib/tests/coverage.py`로 볼 수 있습니다.
  - 카테고리×엔진×항목 421개 중 266개를 양방향으로 확인했습니다.
  - 155개는 사유를 기록하고 면제했습니다(정책 판단 항목, 해당 엔진이 가이드 대상이 아님, CI에서 만들 수 없는 환경).
  - 누락은 0건입니다.

| 카테고리 | 검증한 대상(버전) | 실행 위치 | 양방향 확인 / 면제 |
|---|---|---|---|
| 01_unix | Debian 12.15, OpenSSH 9.2p1 (POSIX sh) | Docker `debian:12` | 58 / 9 |
| 01_unix rhel 계열 | Rocky Linux 9.8 (authselect minimal PAM, OpenSSH 9.9p1, cronie, systemd 252) | Docker `rockylinux/rockylinux:9` (1.5.0) | Debian 과 같은 케이스 54건 + rhel 전용 5건(authselect faillock·su wheel), 진단 실기 안전 검사 |
| 02_windows | Windows Server 2025 Datacenter (10.0.26100, en-US), PowerShell 5.1.26100 | GitHub `windows-2025` 러너 (IIS·FTP·DNS·SNMP 기능 설치) | 49 / 15 |
| 03_web Apache | Apache httpd 2.4.69 (공식 이미지) | Docker `httpd:2.4` | 16 / 10 |
| 03_web Apache(Debian 패키지) | apache2 2.4.68-1~deb12u1 | Docker `debian:12` | 16 / 10 |
| 03_web Nginx | nginx 1.31.8 | Docker `nginx:latest` | 15 / 11 |
| 03_web Tomcat | Apache Tomcat 10.1.61 | Docker `tomcat:10` | 18 / 8 |
| 03_web IIS | IIS 10.0 (Windows Server 2025, URL Rewrite·ARR 포함) | `windows-2025` 러너 | 20 / 6 |
| 05_network | Cisco IOS 15.2 형식 running-config 텍스트 (실장비 아님), Python 3.12 | Ubuntu 24.04 러너 | 31 / 7 |
| 07_pc | PC 18항목을 Windows Server 2025 러너에서 실행 (Windows 10/11 클라이언트 실기는 아님) | `windows-2025` 러너 | 12 / 6 |
| 08_dbms MySQL | MySQL 8.4.13 | Docker `mysql:8` | 7 / 19 |
| 08_dbms PostgreSQL | PostgreSQL 16.15 | Docker `postgres:16` | 5 / 21 |
| 08_dbms Oracle | Oracle AI Database 26ai Free | Docker `gvenzl/oracle-free:23-slim` (다이제스트 고정, 주간·수동 job) | 14 / 12 |
| 08_dbms MSSQL | SQL Server 2025 LocalDB 17.0.4025.3 (RTM-CU3) | `windows-2025` 러너 | 5 / 21 |

- 버전은 위 실행의 job summary에 남은 값입니다. linux-integration job 의 "엔진 버전 기록" 단계가 매 실행마다 남깁니다.
- Oracle 을 뺀 이미지 태그는 고정하지 않았습니다. 그래서 이후 실행은 더 새로운 마이너 버전으로 돌 수 있고, 실제 버전은 각 실행의 summary 에서 확인할 수 있습니다.
- DBMS 의 면제가 많은 이유는 두 가지입니다. 가이드가 해당 엔진을 대상으로 하지 않는 항목이 많고, 계정 필요 여부 같은 정책 판단 항목은 항상 MANUAL 이기 때문입니다.

**위 표에 없는 환경은 코드상 분기는 있어도 실기 검증을 하지 않았습니다**:
- Unix: RHEL·Alma 등 Rocky 이외의 rhel 계열(같은 패키지 계열이라 차이는 작음), SUSE, Solaris/AIX/HP-UX
- Windows: Server 2025 이외 버전, 한글 Windows, 도메인 컨트롤러, Windows 10/11 클라이언트 실기
- DB: 정식 MSSQL 인스턴스, 표의 버전과 다른 DB·웹 서버 메이저 버전
- Network: Cisco 실장비 출력

운영에 쓰기 전에 [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) §2(검증 환경의 한계)와 §3(검토 필요 사항)을 확인하세요.

## 빠른 시작
### Unix (Linux rhel/debian)
```sh
sh 01_unix/run.sh -l              # 항목 목록 확인
sudo sh 01_unix/run.sh            # 전체 진단 (환경 자동 감지, root 권장)
sh 01_unix/run.sh -i U-01,U-05    # 특정 항목만
sh 01_unix/run.sh -g 1            # 특정 하위분류만 (1=계정 관리 ... 5=로그 관리)
```
자동 조치(진단과 완전히 분리된 별도 진입점, 기본은 dry-run):
```sh
sh 01_unix/fix.sh -r output/<host>_01_<시각>/result.json                 # dry-run(미리보기만)
sh 01_unix/fix.sh -r <result.json> -i U-01,U-16 --apply                  # 지정 항목만 실제 적용
sh 01_unix/fix.sh -r <result.json> --apply --yes                         # 적용 전 변경 목록 확인(1회) 생략(confirm은 항상 개별 확인)
sh 01_unix/fix.sh --rollback output/<host>_01_fix_<시각>/                 # 백업에서 원복
```

### Windows Server
```powershell
.\02_windows\run.ps1 -l                     # 항목 목록 확인
.\02_windows\run.ps1                        # 전체 진단 (관리자 권한 권장)
.\02_windows\run.ps1 -i W-01,W-04           # 특정 항목만
.\02_windows\run.ps1 -g 1                   # 특정 하위분류만 (1=계정 관리 ... 5=보안 관리)
```
자동 조치(진단과 완전히 분리된 별도 진입점, 기본은 dry-run):
```powershell
.\02_windows\fix.ps1 -ResultJson output\<host>_02_<시각>\result.json          # dry-run(미리보기만)
.\02_windows\fix.ps1 -ResultJson <result.json> -Items W-02,W-18 -Apply        # 지정 항목만 실제 적용
.\02_windows\fix.ps1 -ResultJson <result.json> -Apply -Yes                    # 적용 전 변경 목록 확인(1회) 생략(confirm은 항상 개별 확인)
.\02_windows\fix.ps1 -Rollback output\<host>_02_fix_<시각>\                    # 백업에서 원복
```

### PC (Windows 10/11)
```powershell
.\07_pc\run.ps1 -l                          # 항목 목록 확인
.\07_pc\run.ps1                             # 전체 진단 (관리자 권한 권장)
.\07_pc\run.ps1 -i PC-01,PC-05              # 특정 항목만
.\07_pc\run.ps1 -g 1                        # 특정 하위분류만 (1=계정 관리 ... 4=보안 관리)
```
자동 조치(02_windows/fix.ps1 과 동일한 CLI/흐름):
```powershell
.\07_pc\fix.ps1 -ResultJson output\<host>_07_<시각>\result.json               # dry-run(미리보기만)
.\07_pc\fix.ps1 -ResultJson <result.json> -Items PC-01,PC-15 -Apply           # 지정 항목만 실제 적용
.\07_pc\fix.ps1 -Rollback output\<host>_07_fix_<시각>\                        # 백업에서 원복
```

### Web (Apache/Nginx/Tomcat: sh, IIS: PowerShell)
```sh
sh 03_web/run.sh -l                # 항목 목록 확인
sh 03_web/run.sh                   # 설치된 엔진 자동 탐지 후 일괄 진단 (여러 엔진 동시 가능)
sh 03_web/run.sh -e nginx          # 특정 엔진으로 제한 (apache|nginx|tomcat)
sh 03_web/run.sh -i WEB-01,WEB-04  # 특정 항목만
```
```powershell
.\03_web\run.ps1                     # IIS 설치된 사이트 전체 진단 (관리자 권한 권장)
.\03_web\run.ps1 -i WEB-04,WEB-09    # 특정 항목만
.\03_web\run.ps1 -l                  # 항목 목록 확인 (26항목 전체, IIS 미대상 항목은 실행 시 NA)
```
자동 조치(진단과 완전히 분리된 별도 진입점, 기본은 dry-run — Apache/Nginx/Tomcat 은 `fix.sh`,
IIS 는 `fix.ps1`):
```sh
sh 03_web/fix.sh -r output/<host>_03_<시각>/result.json                 # dry-run(미리보기만)
sh 03_web/fix.sh -r <result.json> -i WEB-04,WEB-16 --apply               # 지정 항목만 실제 적용
sh 03_web/fix.sh -r <result.json> --apply --yes                          # 적용 전 변경 목록 확인(1회) 생략(confirm은 항상 개별 확인)
sh 03_web/fix.sh --rollback output/<host>_03_fix_<시각>/                  # 백업에서 원복
```
```powershell
.\03_web\fix.ps1 -ResultJson output\<host>_03_<시각>\result.json          # dry-run(미리보기만)
.\03_web\fix.ps1 -ResultJson <result.json> -Items WEB-04,WEB-16 -Apply    # 지정 항목만 실제 적용
.\03_web\fix.ps1 -Rollback output\<host>_03_fix_<시각>\                   # 백업에서 원복
```

### DBMS (MySQL/PostgreSQL/Oracle: sh, MSSQL: PowerShell)
```sh
sh 08_dbms/run.sh -e mysql --host 127.0.0.1 --port 3306 --user root   # DB_PASSWORD 환경변수로 비밀번호 전달
sh 08_dbms/run.sh -e postgres --host 127.0.0.1 --db postgres --user postgres
sh 08_dbms/run.sh -e oracle --host 127.0.0.1 --port 1521 --db FREE --user system
sh 08_dbms/run.sh -e mysql -i D-01,D-08             # 특정 항목만
sh 08_dbms/run.sh -l                                # 항목 목록 확인 (26항목 전체)
```
```powershell
.\08_dbms\run.ps1                                   # 로컬(Windows 통합 인증)로 전체 진단
.\08_dbms\run.ps1 -SqlUser sa -SqlHost .            # SQL 인증 ($env:DB_PASSWORD 필요)
.\08_dbms\run.ps1 -i D-01,D-23
```
`-e` 생략 시(sh) 로컬에 구동 중인 엔진을 자동 탐지합니다(단, 여러 엔진이 동시에 감지되면 `-e` 로
명시 지정 필요). MSSQL은 단일 엔진이라 `run.ps1`에 `-e`가 없습니다. 비밀번호는 CLI 인자가 아닌
`DB_PASSWORD` 환경변수로만 전달합니다.

자동 조치(진단과 완전히 분리된 별도 진입점, 기본은 dry-run — MySQL/PostgreSQL/Oracle 은
`fix.sh`, MSSQL 은 `fix.ps1`):
```sh
sh 08_dbms/fix.sh -e mysql -r output/<host>_08_<시각>/result.json              # dry-run(미리보기만)
sh 08_dbms/fix.sh -e mysql -r <result.json> -i D-01,D-11 --apply               # 지정 항목만 실제 적용
sh 08_dbms/fix.sh -e mysql -r <result.json> --apply --yes                      # 적용 전 변경 목록 확인(1회) 생략(confirm은 항상 개별 확인)
sh 08_dbms/fix.sh -e mysql --rollback output/<host>_08_fix_<시각>/              # 백업에서 원복
```
```powershell
.\08_dbms\fix.ps1 -ResultJson output\<host>_08_<시각>\result.json          # dry-run(미리보기만)
.\08_dbms\fix.ps1 -ResultJson <result.json> -Items D-03,D-26 -Apply       # 지정 항목만 실제 적용
.\08_dbms\fix.ps1 -Rollback output\<host>_08_fix_<시각>\                   # 백업에서 원복
```
DB 상태 변경은 파일이 아니라 SQL 실행 결과라 원복은 "원복용 SQL을 다시 실행"하는 방식으로
동작합니다. 일부 항목(D-07/D-19/D-26)은 정적 파라미터라 적용에 DB 서비스 재시작이 필요합니다 —
DB 클라이언트 연결만 영향을 주고 이 스크립트를 실행한 OS 세션에는 영향이 없습니다.

### Network (Cisco IOS, 오프라인 설정파일 분석)
```sh
python 05_network/run.py -f running-config.txt              # 벤더 자동 판별 후 전체 분석
python 05_network/run.py -f running-config.txt -v cisco_ios  # 벤더 수동 지정
python 05_network/run.py -d configs/                         # 디렉터리 내 다수 장비 일괄 분석
python 05_network/run.py -f running-config.txt -i N-01,N-06  # 특정 항목만
python 05_network/run.py -l                                  # 항목 목록 확인 (38항목 전체)
```
다른 카테고리와 달리 대상 장비에는 아무것도 배치하지 않습니다 — 미리 `show running-config` 등으로
수집한 설정 텍스트 파일을 분석자 PC에서 Python으로 분석합니다.

조치도 장비에 직접 적용하지 않고, 검토용 명령어 텍스트 파일만 생성합니다(`--apply`/`--rollback`
없음):
```sh
python 05_network/fix.py -f running-config.txt -r output/<host>_05_<시각>/result.json
python 05_network/fix.py -f running-config.txt -r <result.json> -i N-01,N-06   # 특정 항목만
```
생성된 `remediation_<host>.txt`는 사람이 검토하고 `<placeholder>` 값(관리 IP 대역, 로그/NTP
서버 주소 등)을 실제 값으로 교체한 뒤 콘솔로 직접 입력하는 참고용 스크립트입니다.

모든 카테고리는 동일한 CLI 옵션 문자(`-l/-i/-g/-o/-h`)를 사용합니다 (`CLAUDE.md` "CLI 옵션 문자
통일" 참고). 결과는 언어에 관계없이 `output/<host>_<카테고리번호>_<시각>/` 아래 동일한 구조로
생성됩니다:
- `result.json` / `result.csv` — 기계 판독·표계산용
- `report.html` — 브라우저로 열람 (오프라인 단일 파일)
- `summary.txt` / `run.log` — 요약 · 실행 로그

### 통합 런처 (한 호스트에서 적용 가능한 모든 카테고리 한 번에)
```sh
sh audit.sh                 # Unix 계열: 01_unix + 03_web + 08_dbms(엔진 감지 시)
```
```powershell
.\audit.ps1                 # Windows 계열: 02_windows + 07_pc + 03_web(IIS) + 08_dbms(MSSQL)
```
카테고리별 세부 옵션(`-i`/`-g` 등)은 지원하지 않습니다 - 특정 항목만 보려면 해당 카테고리의
run.*을 직접 실행하세요.

### 다중 호스트 결과 병합
```sh
python lib/merge.py output/*/result.json -o output/merged          # 특정 result.json들 직접 지정
python lib/merge.py --dir output -c 01 -o output/merged_unix        # output/ 아래 01_unix 결과 전부 자동 탐색
```
여러 호스트에서 같은 카테고리를 진단한 결과를 모아 호스트별 준수율 순위, 전사 공통 취약 항목
순위를 `merged_report.html`로 봅니다. 분석자 PC 전용이며 대상 시스템에는 접근하지 않습니다.

## 가이드 데이터 추출·정리
모든 check/fix 구현은 가이드 PDF가 아니라, 아래 스크립트가 생성한 `guide.json`/`guide.md`를
기준으로 진행합니다 (원본 PDF는 저장소에 포함하지 않습니다).
```sh
python lib/extract_guide.py            # 전체 카테고리
python lib/extract_guide.py --only 01_unix
```

## 테스트
매 push/PR마다 [`.github/workflows/test.yml`](.github/workflows/test.yml)이 자동으로
돕니다 — 전체 저장소 정적분석(ShellCheck/PSScriptAnalyzer/Python) + 카테고리별 Docker/
windows-latest 기반 vuln·hardened 픽스처 회귀 테스트, 조치 실적용·원복 테스트, 그리고 **진단 실행 검수**
(`lib/tests/run_safety.sh`·`run_safety_windows.ps1`: 진단 전후 시스템 상태 동일, 비밀값 미저장, 일반 사용자/비관리자
실행 시 거짓 양호 없음, DB 에 읽기 전용 SQL 만 보냄). 로컬에서 직접 돌리려면:
```sh
python3 05_network/tests/run_tests.py  # Docker 불필요
sh 01_unix/tests/run_tests.sh       # Docker 필요
sh 03_web/tests/run_tests.sh        # Docker 필요
sh 08_dbms/tests/run_tests.sh       # Docker 필요 (MySQL/PostgreSQL; Oracle 은 CI oracle job - 08_dbms/tests 참고)
```
`02_windows/tests/run_tests.ps1`, `07_pc/tests/run_tests.ps1`은 **실제 레지스트리를 바꾸고
되돌리지 않으므로 로컬 개발자 PC에서 실행하지 마세요** — windows-latest CI 러너(매 job마다
새로 생성되는 휘발성 VM)에서만 실행하도록 만들어졌습니다.

## 로드맵
| 버전 | 내용 |
|---|---|
| 0.1.0 ✅ | 골격, 가이드 추출·정리본 6종, 공통 모듈, 보고서 템플릿, Unix PoC(U-01~05) |
| 0.2.0 ✅ | Unix 67항목 전체 |
| 0.3.0 ✅ | Windows Server 64항목 |
| 0.4.0 ✅ | PC 18항목 |
| 0.5.0 ✅ | Web 26항목 (Apache/Nginx/Tomcat) |
| 0.6.0 ✅ | DBMS 26항목 중 MySQL/PostgreSQL |
| 0.6.1 ✅ | DBMS: Oracle(sqlplus)/MSSQL(sqlcmd, run.ps1) 추가 |
| 0.7.0 ✅ | Network 38항목 중 Cisco IOS |
| 0.8.0 ✅ | 자동 조치(fix) 공통 인프라 + Unix 58/67항목 |
| 0.8.1 ✅ | Web: IIS 23/26항목 |
| 0.8.2 ✅ | Windows 48/64, PC 11/18 자동 조치(fix) |
| 0.9.0 ✅ | Web(Apache/Nginx/Tomcat) 18/26 자동 조치(fix) |
| 0.9.1 ✅ | Web(IIS) 17/26 자동 조치(fix) |
| 0.9.2 ✅ | DBMS(MySQL/PostgreSQL/Oracle/MSSQL) 20/26 자동 조치(fix) |
| 0.9.3 ✅ | Network(Cisco IOS) 조치 명령어 스크립트 생성 |
| 0.9.4 ✅ | 통합 런처(`audit.sh`/`audit.ps1`), 다중 호스트 보고서 병합(`lib/merge.py`), 저장소 전체 정적분석·실기 검증 |
| 1.0.0 ✅ | 6개 카테고리 완성·검증 |
| 1.1.0 ✅ | 01_unix Solaris/AIX/HP-UX 진단 7항목 확장(문서 기준, 미검증) |
| 1.2.0 ✅ | **환경/벤더 확장 중단, 테스트·유지보수로 전환.** GitHub Actions CI(정적분석 + Docker/windows-latest 기반 회귀 테스트) 도입 |
| 1.2.1~1.3.0 ✅ | 운영 안전성 우선: DB 계정 잠금·무기한 대기·비밀값 저장 방지, 조치 안전장치(백업·문법검사·접속 차단 사전검사·원복 정직성), 업무 영향 항목 등급 하향 |
| 1.3.1 ✅ | Windows Server(CI 러너) 실기 검증: IIS 진단·조치 실적용·원복, MSSQL(LocalDB), 방화벽 안전장치 |
| 1.3.2 ✅ | 진단(run) 전체 검수: 실행 검수 하네스 + 전 파일 코드 대조(약 130건 수정, [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md)) |
| 1.3.3 ✅ | 조치 후속 과제 F-R1~F-R9 해결, 실검증 테스트 교차검증(거짓 PASS 경로 16건 수정 - 원복 누락·무기한 대기 등 실제 결함 추가 발견) |
| 1.4.0 ✅ | 전 항목 양방향 판정 검증(취약·양호 상태를 각각 세팅해 확인, 누락 0 - `lib/tests/coverage.py`), 현 상태 교차검증 결함 X-01~X-09 및 새로 드러난 판정·조치 결함 약 45건 수정 |
| 1.x | 기존 지원 환경 내 버그 수정 및 자동화 정밀도 개선, CI 커버리지 확대(IIS/MSSQL/Oracle/rhel 등) |

## 라이선스 · 출처
- 코드: MIT License ([`LICENSE`](./LICENSE))
- 근거 문서: 한국인터넷진흥원(KISA), 「주요정보통신기반시설 기술적 취약점 분석·평가 방법
  상세가이드」(2026판). 저작권은 원저작자(KISA)에 있으며, 본 저장소는 가이드 원문을 코드로
  옮긴 진단 도구이지 가이드 자체를 재배포하지 않습니다(PDF 미포함).
