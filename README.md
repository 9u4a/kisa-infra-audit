# kisa-infra-audit

주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드(2026판)를 기준으로,
Unix/Windows/Web/Network/PC/DBMS 6개 카테고리를 자동 진단하고 보고서를 생성하는 도구입니다.
가능한 항목은 자동 조치(fix)까지 지원합니다.

> ⚠️ 이 저장소는 **개발 진행 중**(SemVer 0.x)입니다. 현재는 Unix(67항목, Linux 대상), Windows
> Server(64항목), Web(26항목, Apache/Nginx/Tomcat/IIS), PC(18항목, Windows 10/11), DBMS(26항목,
> MySQL/PostgreSQL/Oracle/MSSQL 대상), Network(38항목 중 Cisco IOS 대상) 카테고리가 실제 진단
> 로직으로 구현되어 있습니다. 로드맵은 아래를 참고하세요.

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
| [`01_unix`](./01_unix) | U | 1. UNIX 서버 | 67 | 🟢 67/67 진단 + 58/67 조치(fix) 구현 (Linux) |
| [`02_windows`](./02_windows) | W | 2. Windows 서버 | 64 | 🟢 64/64 진단 + 48/64 조치(fix) 구현 |
| [`03_web`](./03_web) | WEB | 3. 웹 서비스 | 26 | 🟢 26/26 구현 (Apache/Nginx/Tomcat), IIS 23/26 구현 (JEUS/WebtoB 는 이후) |
| [`05_network`](./05_network) | N | 5. 네트워크 장비 | 38 | 🟡 Cisco IOS 구현 (Juniper/Alteon/Passport/Piolink 는 이후) |
| [`07_pc`](./07_pc) | PC | 7. PC | 18 | 🟢 18/18 진단 + 11/18 조치(fix) 구현 |
| [`08_dbms`](./08_dbms) | D | 8. DBMS | 26 | 🟢 MySQL/PostgreSQL/Oracle/MSSQL 구현 (Altibase/Tibero/Cubrid 는 이후) |

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
sh 01_unix/fix.sh -r <result.json> --apply --yes                         # auto 등급 일괄 적용(confirm은 항상 개별 확인)
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
.\02_windows\fix.ps1 -ResultJson <result.json> -Apply -Yes                    # auto 등급 일괄 적용(confirm은 항상 개별 확인)
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

모든 카테고리는 동일한 CLI 옵션 문자(`-l/-i/-g/-o/-h`)를 사용합니다 (`CLAUDE.md` "CLI 옵션 문자
통일" 참고). 결과는 언어에 관계없이 `output/<host>_<카테고리번호>_<시각>/` 아래 동일한 구조로
생성됩니다:
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
| 0.4.0 ✅ | PC 18항목 |
| 0.5.0 ✅ | Web 26항목 (Apache/Nginx/Tomcat; IIS/JEUS/WebtoB 는 이후) |
| 0.6.0 ✅ | DBMS 26항목 중 MySQL/PostgreSQL |
| 0.6.1 ✅ | DBMS: Oracle(sqlplus)/MSSQL(sqlcmd, run.ps1) 추가 (Altibase/Tibero/Cubrid 는 이후) |
| 0.7.0 ✅ | Network 38항목 중 Cisco IOS (Juniper/Alteon/Passport/Piolink 는 이후) |
| 0.8.0 ✅ | 자동 조치(fix) 공통 인프라 + Unix 58/67항목 |
| 0.8.1 ✅ | Web: IIS 23/26항목 (JEUS/WebtoB 는 이후) |
| 0.8.2 ✅ | Windows 48/64, PC 11/18 자동 조치(fix) |
| 0.9.0 | Web/DBMS fix, Network 조치 스크립트, 통합 런처, 다중 호스트 보고서 병합 |
| 1.0.0 | 6개 카테고리 완성·검증 |

## 라이선스 · 출처
- 코드: MIT License ([`LICENSE`](./LICENSE))
- 근거 문서: 한국인터넷진흥원(KISA), 「주요정보통신기반시설 기술적 취약점 분석·평가 방법
  상세가이드」(2026판). 저작권은 원저작자(KISA)에 있으며, 본 저장소는 가이드 원문을 코드로
  옮긴 진단 도구이지 가이드 자체를 재배포하지 않습니다(PDF 미포함).
