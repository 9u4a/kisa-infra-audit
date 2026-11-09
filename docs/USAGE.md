# 사용법

카테고리별 진단·조치·병합 명령입니다. 개요는 [README](../README.md)를 보세요.

## Unix (Linux rhel/debian)
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

## Windows Server
Windows 10/11 의 기본 실행 정책(Restricted)과 인터넷·메일·USB 로 받은 파일 표시(Zone.Identifier) 때문에 `.ps1` 이 실행되지 않을 수 있습니다.
시스템 정책을 바꾸지 말고 **그 PowerShell 창에서만** 허용합니다(관리자 권한 PowerShell 에서):
```powershell
Get-ChildItem -Path .\ -Recurse -Include *.ps1,*.psm1 | Unblock-File   # 받은 파일 표시 제거(도구 폴더에서 1회)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force          # 현재 창에서만 허용(창을 닫으면 원래대로)
```
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

## PC (Windows 10/11)
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

## Web (Apache/Nginx/Tomcat: sh, IIS: PowerShell)
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

## DBMS (MySQL/PostgreSQL/Oracle: sh, MSSQL: PowerShell)
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

## Network (Cisco IOS, 오프라인 설정파일 분석)
```sh
python 05_network/run.py -f running-config.txt              # 벤더 자동 판별 후 전체 분석
python 05_network/run.py -f running-config.txt -e cisco_ios  # 벤더 수동 지정(예전 -v 도 같은 뜻)
python 05_network/run.py -d configs/                         # 디렉터리 내 다수 장비 일괄 분석
python 05_network/run.py -f running-config.txt -i N-01,N-06  # 특정 항목만
python 05_network/run.py -l                                  # 항목 목록 확인 (38항목 전체)
```
다른 카테고리와 달리 대상 장비에는 아무것도 배치하지 않습니다 — 미리 `show running-config` 등으로
수집한 설정 텍스트 파일을 분석자 PC에서 Python으로 분석합니다.
- 입력은 Cisco IOS 설정 전체(마지막 `end` 줄까지)여야 합니다. NX-OS·ASA·IOS XR 설정은 `-e cisco_ios` 로 지정해도
  분석하지 않고 오류로 끝냅니다. `end` 줄이 없는 잘린 설정은 분석하되 양호/해당없음 판정을 모두 `오류`로 바꿉니다
  (빠진 뒷부분에 설정이 있을 수 있어 "설정 없음"을 근거로 양호라고 할 수 없음).
- 종료 코드: 모든 파일을 분석하면 0, 읽기·벤더 판별·입력 검증에 실패한 파일이 하나라도 있으면 1(`-d` 에서는 나머지
  파일은 계속 분석).

조치도 장비에 직접 적용하지 않고, 검토용 명령어 텍스트 파일만 생성합니다(`--apply`/`--rollback`
없음):
```sh
python 05_network/fix.py -f running-config.txt -r output/<host>_05_<시각>/result.json
python 05_network/fix.py -f running-config.txt -r <result.json> -i N-01,N-06   # 특정 항목만
```
생성된 `remediation_<host>.txt`는 사람이 검토하고 `<placeholder>` 값(관리 IP 대역, 로그/NTP
서버 주소 등)을 실제 값으로 교체한 뒤 콘솔로 직접 입력하는 참고용 스크립트입니다.

모든 카테고리는 동일한 CLI 옵션 문자(`-l/-i/-g/-o/-h`)를 사용합니다. 결과는 언어에 관계없이 `output/<host>_<카테고리번호>_<시각>/` 아래 동일한 구조로
생성됩니다:
- `result.json` / `result.csv` — 기계 판독·표계산용
- `report.html` — 브라우저로 열람 (오프라인 단일 파일)
- `summary.txt` / `run.log` — 요약 · 실행 로그

## 조치 정책 모드 (무인 조치, 1.6.0)
confirm 항목까지 y/N 없이 적용하려면 승인자가 작성한 정책 파일을 준다. 실제 적용은 여전히 `--apply`/`-Apply` 가 필요하고, 없으면 정책을
적용한 dry-run 이다.
```text
# 정책 파일 (UTF-8, 줄 단위, # 주석)
category=01            # 실행 카테고리와 같아야 함(01/02/03/05/07/08)
expires=2026-12-31     # 그날까지 유효
approver=홍길동
U-01
U-18
U-36:irreversible      # 원복 불가·업무 영향 항목(docs/FIX_IMPACT.md "필요")은 :irreversible 이 있어야 적용

[host:web01]           # 호스트별 제외(대소문자 무시)
-U-18

[host:*]               # 나머지 호스트 허용. 실행 호스트에 맞는 구역도 [host:*] 도 없으면 거부
```
```sh
sh 01_unix/fix.sh -r <result.json> --policy policy.txt --operator 김점검            # 정책 적용 dry-run
sh 01_unix/fix.sh -r <result.json> --policy policy.txt --operator 김점검 --apply    # 무인 적용
```
```powershell
._windowsix.ps1 -ResultJson <result.json> -Policy policy.txt -Operator 김점검 -Apply
```
```sh
python 05_network/fix.py -f running-config.txt -r <result.json> --policy policy.txt --operator 김점검
```
- 대상 = 진단 VULN ∩ `-i` ∩ 정책 승인 − 호스트 제외. 나머지는 `POLICY_SKIPPED`(사유: 정책 미승인 / 호스트 제외 / irreversible 플래그 필요).
- 코드·키는 대소문자 구분. 없는 코드·중복·알 수 없는 키·만료·카테고리 불일치는 줄 번호와 함께 exit 2(아무것도 바꾸지 않음).
- `--force` 는 결과 파일 확인(X-06)만 무시하고 정책 검사는 무시하지 않는다. 비밀번호 직접 입력 조치는 비대화형이면 건너뛴다.
- 출력 폴더 `audit.txt` 에 실행자·로그인 계정·승인자·정책 SHA-256·시각·건수·실패 코드가 남는다.

## 통합 런처 (한 호스트에서 적용 가능한 모든 카테고리 한 번에)
```sh
sh audit.sh                 # Unix 계열: 01_unix + 03_web + 08_dbms(엔진 감지 시)
```
```powershell
.\audit.ps1                 # Windows 계열: 02_windows + 07_pc + 03_web(IIS) + 08_dbms(MSSQL)
```
카테고리별 세부 옵션(`-i`/`-g` 등)은 지원하지 않습니다 - 특정 항목만 보려면 해당 카테고리의
run.*을 직접 실행하세요.

## 다중 호스트 결과 병합
```sh
python lib/merge.py output/*/result.json -o output/merged          # 특정 result.json들 직접 지정
python lib/merge.py --dir output -c 01 -o output/merged_unix        # output/ 아래 01_unix 결과 전부 자동 탐색
```
여러 호스트에서 같은 카테고리를 진단한 결과를 모아 호스트별 준수율 순위, 전사 공통 취약 항목
순위를 `merged_report.html`로 봅니다. 분석자 PC 전용이며 대상 시스템에는 접근하지 않습니다.

조치 전후 비교와 수동점검 사람 판정(1.6.0):
```sh
python lib/merge.py --diff output/before output/after -c 01 -o output/diff                 # 조치 전 / 후 결과 폴더
python lib/merge.py output -c 01 --verdicts manual_verdicts_web01.json -o output/merged    # 사람 판정 반영
```
- `--diff` 는 신규 취약(맨 위)·조치 완료·미조치·확인 필요·변화 없음 양호로 나눠 `diff_report.html`·`diff.csv`·`diff_summary.txt` 를 만든다.
- `report.html` 에서 수동점검 항목을 펼쳐 취약/양호와 사유를 입력하고 `manual_verdicts.json` 을 내려받는다. 같은 진단 결과(host·category·
  생성 시각)에만 반영되며 result.json 은 바뀌지 않는다.

## 가이드 데이터 추출·정리
모든 check/fix 구현은 가이드 PDF가 아니라, 아래 스크립트가 생성한 `guide.json`/`guide.md`를
기준으로 진행합니다 (원본 PDF는 저장소에 포함하지 않습니다).
```sh
python lib/extract_guide.py            # 전체 카테고리
python lib/extract_guide.py --only 01_unix
```
