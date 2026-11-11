# kisa-infra-audit

KISA 「주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드」(2026판)를 기준으로
6개 분야 239개 항목을 진단하고, 가능한 항목은 백업·원복이 되는 자동 조치까지 하는 도구입니다.

[![test](https://github.com/9u4a/kisa-infra-audit/actions/workflows/test.yml/badge.svg)](https://github.com/9u4a/kisa-infra-audit/actions/workflows/test.yml)

| | |
|---|---|
| 범위 | Unix 67 · Windows 64 · Network 38 · Web 26 · DBMS 26 · PC 18 = **239개 항목** |
| 대상 무설치 | 대상 서버는 OS 기본 도구만 사용합니다 (POSIX sh / PowerShell 5.1) |
| 진단과 조치 분리 | `run`은 읽기만 하고, `fix`는 dry-run 기본 → `--apply` → `--rollback` 순서로 동작합니다 |
| 검증 | 카테고리×엔진×항목 421개 조합 중 **265개 양방향 확인**, 156개 사유 기록 후 면제, **누락 0** |
| CI | GitHub Actions **20개 환경**(매 push 15 + 주간 5)에서 회귀 테스트 — [검증된 실행 환경](#검증된-실행-환경) |
| 결함 수정 | 양방향 검증(1.4.0)으로 판정·조치 결함 **50건**(교차검증 9 + 양방향 검증 41), 진단 신뢰성 검수(1.5.0)로 **35건**(거짓 양호 24 · 거짓 취약 1 · 중단·보안 10) 수정 — [KNOWN_ISSUES](KNOWN_ISSUES.md) §1-8·§6 |

## 왜 만들었나
PC 보안 점검 솔루션의 "점검 → 원클릭 조치 → 재점검" 흐름을 쓰면서,
같은 흐름을 서버·웹·DB·네트워크에 KISA 가이드 기준으로 만들어 보자고 시작했습니다.
가장 위험한 결과는 "취약한데 양호"라고 판단하는 것이라, 기능을 늘리는 대신 1.2.0부터 판정 검증에 집중했습니다.

> ⚠️ 운영 서버에 쓰기 전에 [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md)(알려진 문제·미검증 범위·검증 환경 한계)를 확인하세요.
> 진단은 root/관리자 권한으로 실행해야 합니다. 권한이 없으면 확인하지 못한 항목은 양호가 아니라 ERROR 로 표시됩니다.

## 핵심 원칙
1. **가이드 원문 우선** — 항목명·판단기준·조치방법은 가이드 원문 그대로 사용, 자동화에 꼭 필요한
   경우에만 보완(사유는 `deviation` 필드/CHANGELOG에 기록)
2. **진단/조치 분리** — 진단(`run.*`)은 대상 설정을 절대 변경하지 않음. 조치(`fix.*`)는 별도
   진입점에서 백업·확인 절차를 거쳐 수행
3. **대상 무설치** — 대상 호스트는 OS 기본 도구만 사용 (Unix=POSIX sh, Windows=PowerShell 5.1).
   Python은 분석자 PC 전용(가이드 추출, 네트워크 설정 분석, 다중 호스트 보고서 병합)

## 카테고리 (가이드 장 번호 기준)
| 폴더 | 코드 | 가이드 장 | 항목 수 | 상태 |
|---|---|---|---|---|
| [`01_unix`](./01_unix) | U | 1. UNIX 서버 | 67 | 🟢 67/67 진단(Linux 전체 + Solaris/AIX/HP-UX 7항목, 미검증) + 58/67 조치(Linux) |
| [`02_windows`](./02_windows) | W | 2. Windows 서버 | 64 | 🟢 64/64 진단 + 48/64 조치(fix) 구현 |
| [`03_web`](./03_web) | WEB | 3. 웹 서비스 | 26 | 🟢 Apache/Nginx/Tomcat 26/26 진단 + 18/26 조치(fix), IIS 23/26 진단 + 17/26 조치 |
| [`05_network`](./05_network) | N | 5. 네트워크 장비 | 38 | 🟢 Cisco IOS 38/38 진단 + 조치 명령어 생성 구현 |
| [`07_pc`](./07_pc) | PC | 7. PC | 18 | 🟢 18/18 진단 + 11/18 조치(fix) 구현 |
| [`08_dbms`](./08_dbms) | D | 8. DBMS | 26 | 🟢 MySQL/PostgreSQL/Oracle/MSSQL 진단 + 조치(fix) 구현 |

## 검증된 실행 환경
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
| 01_unix rhel 계열 | Rocky Linux 9.8 (authselect minimal PAM, OpenSSH 9.9p1, cronie, systemd 252) | Docker `rockylinux/rockylinux:9` | Debian 과 같은 케이스 + rhel 전용(authselect faillock·su wheel) 총 82건, 진단 실기 안전 검사 |
| 02_windows | Windows Server 2025 Datacenter (10.0.26100, en-US), PowerShell 5.1.26100 | GitHub `windows-2025` 러너 (IIS·FTP·DNS·SNMP 기능 설치) | 49 / 15 |
| 02_windows Server 2022 | Windows Server 2022 Datacenter (en-US), PowerShell 5.1 | GitHub `windows-2022` 러너 (주간·수동 job) | 02_windows·07_pc 같은 케이스(OS 차이는 케이스 `expect_os` 에 사유 기록) |
| 03_web Apache | Apache httpd 2.4.69 (공식 이미지) | Docker `httpd:2.4` | 16 / 10 |
| 03_web Apache(Debian 패키지) | apache2 2.4.68-1~deb12u1 | Docker `debian:12` | 16 / 10 |
| 03_web Apache(RHEL 패키지) | httpd 2.4.62-13.el9_8.9 | Docker `rockylinux/rockylinux:9` | 전역 vuln/hardened 픽스처·조치 안전·진단 실기 안전 검사(항목별 케이스는 공식 이미지·Debian 기준) |
| 03_web Tomcat(RHEL 패키지) | tomcat 9.0.120-2.el9_8 | Docker `rockylinux/rockylinux:9` | 위와 같음, 조치 후 tomcat 계정 읽기 확인 |
| 03_web Nginx | nginx 1.31.8 | Docker `nginx:latest` | 15 / 11 |
| 03_web Tomcat | Apache Tomcat 10.1.61 | Docker `tomcat:10` | 18 / 8 |
| 03_web 버전 matrix | Tomcat 9.0.123·11.0.27, nginx 1.30.6(stable) | Docker `tomcat:9`·`tomcat:11`·`nginx:stable` (주간·수동 job) | 기본 태그와 같은 기대값으로 전역 픽스처·조치·운영 안전·항목별 케이스 |
| 03_web IIS | IIS 10.0 (Windows Server 2025, URL Rewrite·ARR 포함) | `windows-2025` 러너 | 19 / 7 |
| 05_network | Cisco IOS 15.2 형식 running-config 텍스트 (실장비 아님), Python 3.12 | Ubuntu 24.04 러너 | 31 / 7 |
| 07_pc | PC 18항목을 Windows Server 2025 러너에서 실행 (Windows 10/11 클라이언트 실기는 아님) | `windows-2025` 러너 | 12 / 6 |
| 07_pc 실 PC(수동) | Windows 11 Home 25H2 (10.0.26200, ko-KR), PowerShell 5.1 | 사용자 PC 1대에서 관리자 권한으로 읽기 전용 진단 (2026-11-06) | 18항목 오류 0, 판정 18건을 독립 명령으로 대조, 콘솔 코드페이지 949·65001 결과 동일 |
| 02_windows 한글 Server(수동 검증, G-07) | Windows Server 2022 Standard 평가판 (10.0.20348) + ko-KR 언어 팩, 표시 언어·시스템 로캘 ko-KR, 코드페이지 949, PowerShell 5.1.20348 | 분석자 PC VMware VM, 독립 서버 (2026-11-10~11) | 진단·조치 안전 검사 + 정책 모드 전체 적용(VULN 16) → 원복: 전부 조치 후 GOOD·원복 후 VULN, 남은 차이는 원복 불가로 고지된 W-17 기본 공유뿐 |
| 02_windows 도메인 컨트롤러(수동 검증, G-07) | 위 VM 을 g07.lab 새 포리스트 주 DC 로 승격 | 분석자 PC VMware VM (2026-11-11) | 같은 검사(VULN 18): 원복 후 상태 스냅샷 차이 0, DC 에서 비관리자 실행 검사(S6)는 로컬 계정이 없어 생략 |
| 07_pc 한글 Windows 11(수동 검증, G-07) | Windows 11 Enterprise 평가판 (10.0.26300, ko-KR), PowerShell 5.1.26100 | 분석자 PC VMware VM (2026-11-11) | 진단·조치 안전 검사 + 정책 모드 전체 적용(VULN 5) → 원복: 남은 차이는 원복 불가로 고지된 PC-04 기본 공유뿐 |
| 01_unix·03_web SELinux(수동 검증, G-07) | Rocky Linux 9.8 (커널 5.14.0-687), SELinux enforcing(targeted), ko_KR.UTF-8, httpd | 분석자 PC VMware VM (2026-11-10) | 01_unix 67항목(VULN 11)·03_web 26항목(VULN 12) 정책 모드 전체 적용 → 원복: 상태 스냅샷(해시·권한·SELinux 컨텍스트) 차이 0, AVC 거부 0, 라벨 불일치 0, 서비스 정상 |
| 08_dbms MySQL | MySQL 8.4.13 | Docker `mysql:8` | 7 / 19 |
| 08_dbms PostgreSQL | PostgreSQL 16.15 | Docker `postgres:16` | 5 / 21 |
| 08_dbms 버전 matrix | MySQL 8.0.46, PostgreSQL 14.24·18.6 | Docker `mysql:8.0`·`postgres:14`·`postgres:18` (주간·수동 job) | 기본 태그와 같은 기대값으로 원격 픽스처·조치·운영 안전·항목별 케이스 |
| 08_dbms Oracle | Oracle AI Database 26ai Free | Docker `gvenzl/oracle-free:23-slim` (다이제스트 고정, 주간·수동 job) | 14 / 12 |
| 08_dbms MSSQL | SQL Server 2025 LocalDB 17.0.4025.3 (RTM-CU3) | `windows-2025` 러너 | 5 / 21 |
| 08_dbms MSSQL(정식 인스턴스) | SQL Server 2022 Express 16.0.1000.6 (RTM, 혼합 인증) | `windows-2025` 러너 + choco `sql-server-express` (주간·수동 job) | LocalDB 와 같은 판정·케이스 11건·운영 안전 |

- 버전은 위 실행의 job summary에 남은 값입니다. linux-integration job 의 "엔진 버전 기록" 단계가 매 실행마다 남깁니다.
- Oracle 을 뺀 이미지 태그는 고정하지 않았습니다. 그래서 이후 실행은 더 새로운 마이너 버전으로 돌 수 있고, 실제 버전은 각 실행의 summary 에서 확인할 수 있습니다.
- DBMS 의 면제가 많은 이유는 두 가지입니다. 가이드가 해당 엔진을 대상으로 하지 않는 항목이 많고, 계정 필요 여부 같은 정책 판단 항목은 항상 MANUAL 이기 때문입니다.

**위 표에 없는 환경은 코드상 분기는 있어도 실기 검증을 하지 않았습니다**:
- Unix: RHEL·Alma 등 Rocky 이외의 rhel 계열(같은 패키지 계열이라 차이는 작음), SUSE, Solaris/AIX/HP-UX
- Windows: Server 2025·2022 이외 버전, 한글 Windows Server, 도메인 컨트롤러, Windows 10·Pro/Enterprise 에디션(Windows 11 Home 은 수동 1대), 클라이언트에서의 조치 적용
- DB·Web: SQL Server Standard/Enterprise, 표에 없는 DB·웹 서버 메이저 버전
- Network: Cisco 실장비 출력

운영에 쓰기 전에 [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) §2(검증 환경의 한계)와 §3(검토 필요 사항)을 확인하세요.

## 빠른 시작
전 카테고리 명령(Windows·Web·DBMS·Network, 다중 호스트 병합, 가이드 추출)은 [`docs/USAGE.md`](docs/USAGE.md)에 있습니다.

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

### 통합 런처 (한 호스트에서 적용 가능한 모든 카테고리 한 번에)
```sh
sh audit.sh                 # Unix 계열: 01_unix + 03_web + 08_dbms(엔진 감지 시)
```
```powershell
.\audit.ps1                 # Windows 계열: 02_windows + 07_pc + 03_web(IIS) + 08_dbms(MSSQL)
```
카테고리별 세부 옵션(`-i`/`-g` 등)은 지원하지 않습니다 - 특정 항목만 보려면 해당 카테고리의
run.*을 직접 실행하세요.

결과는 카테고리에 관계없이 `output/<host>_<카테고리번호>_<시각>/` 아래 같은 구조로 생성됩니다:
- `result.json` / `result.csv` — 기계 판독·표계산용
- `report.html` — 브라우저로 열람 (오프라인 단일 파일)
- `summary.txt` / `run.log` — 요약 · 실행 로그

모든 카테고리는 동일한 CLI 옵션 문자(`-l/-i/-g/-o/-h`, 환경/엔진 지정이 필요한 카테고리는 `-e`)를 사용합니다.
05_network 의 벤더 지정도 `-e` 입니다(예전 `-v` 는 하위 호환으로 계속 받습니다).

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

테스트가 망가진 check 를 실제로 잡는지는 변이 검증(`python3 lib/tests/mutation.py <카테고리>`, CI 주간 `mutation` job)으로 확인합니다.

릴리스 전 확인 항목은 [`.github/release-checklist.md`](.github/release-checklist.md)에 있습니다.

## 로드맵
| 버전 | 내용 |
|---|---|
| 0.1 ~ 1.0 ✅ | 6개 분야 239항목 진단·자동 조치 구현(Network 는 조치 명령어 생성), 통합 런처·다중 호스트 병합 |
| 1.1.0 ✅ | 01_unix Solaris/AIX/HP-UX 진단 7항목(문서 기준, 미검증) |
| 1.2.0 ✅ | **환경·벤더 확장 중단, 테스트·유지보수 전환** — 기능 대신 판정 정확도에 집중, GitHub Actions CI 도입 |
| 1.2.1 ~ 1.3.3 ✅ | 운영 안전 기준(진단 S1~S7, 조치 F1~F6), 진단 실행 검수 하네스, 전 파일 코드 대조(약 130건 수정), 거짓 PASS 경로 16건 수정 |
| 1.4.0 ✅ | 전 항목 양방향 판정 검증(누락 0), 판정·조치 결함 50건 수정(교차검증 X-01~X-09 9건 + 양방향 검증 41건) |
| 1.4.1 ✅ | 조치 등급·조치 스크립트 일관성 검사, 결정 대기 항목(Q-01~Q-06) 처리 |
| 1.5.0 ✅ | Rocky 9·RHEL 패키지·Server 2022·MSSQL Express·엔진 버전 matrix·한글 출력 파싱·변이 검증, 진입점 lib 화, 진단 신뢰성 전체 검수(35건 수정) |
| 1.6.0 🚧 | 정책 파일 기반 무인 조치·irreversible 플래그·감사 기록, 조치 전후 비교, 수동점검 사람 판정(G-01~06 구현, G-07 VM 수동 검증 완료, G-08 외부 검토 남음) |

## 라이선스 · 출처
- 코드: MIT License ([`LICENSE`](./LICENSE)), 출처 고지 [`NOTICE`](./NOTICE)
- 근거 문서: 한국인터넷진흥원(KISA), 「주요정보통신기반시설 기술적 취약점 분석·평가 방법
  상세가이드」(2026판). 저작권은 원저작자(KISA)에 있으며, 본 저장소는 가이드 원문을 코드로
  옮긴 진단 도구이지 가이드 자체를 재배포하지 않습니다(PDF 미포함).
