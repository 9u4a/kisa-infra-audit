# 알려진 문제·한계 (KNOWN_ISSUES)

운영 서버에서 이 도구를 쓰기 전에 확인해야 할 **알려진 문제·미검증 범위**를 한곳에 모은다. 해결한 항목은
`해결(버전)`으로 표시하고 지우지 않는다. 기준은 루트 운영 안전 기준이다.
- 진단: S1 설정 무변경 · S2 무기한 대기 금지 · S3 계정 잠금 금지 · S4 부하 최소화 · S5 비밀값 미저장 ·
  S6 확인 못 한 것은 GOOD 금지 · S7 중복 실행·중단 대비
- 조치: F1~F6

상태 표기는 `열림`, `해결(x.y.z)`, `한계`(설계상·환경상 해소 불가, 결과 해석 시 유의) 세 가지다.

---

## 1. 진단(run) 전체 검수 — 2026-10-27 (1.3.1 기준)

조치(fix)를 실제로 적용·원복해 본 것과 같은 방식으로 진단도 검수했다.

- **실행 검수**(`lib/tests/run_safety.sh`): Docker 컨테이너에서 진단을 실제로 돌린다.
  - 전후 파일시스템·/etc 내용·프로세스·/tmp 비교
  - 비밀값 잔존, 출력물 권한 확인
  - 일반 사용자 실행 결과와 비교해 거짓 양호 확인
  - 음성 대조(일부러 /etc 에 쓰기, 비밀값 노출)로 검사 자체가 문제를 잡아내는지 확인함
- **코드 검수**: 4개 영역 전 파일을 읽어 위 기준으로 대조했다. 코드 근거를 확인한 것만 남겼다.

**결론**
- S1(진단이 설정을 바꿈)은 실행 검수·코드 검수 모두에서 위반 없음.
- 문제는 대부분 **S6(확인 못 한 것·잘못 읽은 것을 GOOD 으로 판정)** 이다.
  - 공용 헬퍼(권한 비교, Include 해석, 경로 탐색)의 결함이 여러 항목에 동시에 퍼진다.

### 1-1. 공통(lib, 진입점)

| ID | 심각도 | 기준 | 내용 | 상태 |
|---|---|---|---|---|
| R-01 | 상 | S7 | check 하나가 죽으면(`set -u` 미설정 변수 등) 진단 전체가 결과 없이 끝남. U-61 에서 snmpd.conf 의 `rocommunity <값>`(소스 생략) 한 줄로 재현됨. | 해결(1.3.2): `run_check_isolated` 서브셸 격리, U-61 `${3:-}` |
| R-02 | 상 | S5 | 결과 폴더는 700 인데 안의 result.json·raw/*.txt 가 644. 폴더를 복사·압축하면 그대로 남이 읽음. | 해결(1.3.2): 진단 시작 시 umask 077 |
| R-03 | 상 | S6 | `check_owner_perm` 등이 8진수 권한을 10진수로 비교함. 예: 622≤640, 0626≤644, 0444≤600 이 통과해 world-writable/readable 파일이 GOOD. 01_unix·03_web·08_dbms 공용 + U-37/40/67, WEB-14 인라인. | 해결(1.3.2): `perm_within`/`perm_exceeds` 비트 비교, 조치 5개 파일도 동일하게 |
| R-04 | 중 | S6 | `json_escape` 가 TAB/CR 외 제어문자(ESC 등)를 이스케이프하지 않음. 파일명에 ESC 가 있으면 result.json 이 깨지고 보고서가 빈 화면. | 해결(1.3.2): 제어문자 제거 |
| R-05 | 중 | S6 | sh 진입점이 PATH 를 정하지 않음. cron/비 root 환경에서 /usr/sbin 의 postconf·sendmail·named·rpcinfo 를 못 찾아 "미설치=GOOD". | 해결(1.3.2): lib/common.sh 에서 PATH 앞에 /usr/sbin:/usr/bin:/sbin:/bin |
| R-06 | 중 | S7 | 진단(run)에 중복 실행 잠금이 없음(출력 폴더는 PID 로 분리됨). 전체 `find /` 가 겹쳐 부하 2배. | 해결(1.3.2): `run_lock_acquire`(결과 기본 폴더의 mkdir 잠금, 죽은 PID 잠금은 정리) |
| R-07 | 중 | S2 | `run_to` 에 `timeout -k` 가 없어 TERM 을 무시하는 자식을 계속 기다림. `low_prio` 의 `ionice -c3` 는 I/O 가 계속되는 서버에서 사실상 무기한 대기 가능. | 해결(1.3.2): `timeout -k 5`, `ionice -c2 -n7` |
| R-08 | 중 | S7 | 부분 결과 trap 이 INT/TERM 만 잡음. SSH 끊김(HUP)에는 result.partial.json 이 남지 않음. | 해결(1.3.2): HUP 도 부분 결과 저장 |
| R-09 | 하 | S1 | `-i ../../x` 같은 항목 코드를 검증하지 않아 임의 경로의 .sh 를 root 로 source 할 수 있음. `-o` 로 남이 만든 기존 디렉터리를 그대로 받아들임. | 해결(1.3.2): `code_is_known` 으로 -i 코드 검증(-o 기존 폴더 문제는 열림) |
| R-10 | 중 | S6 | (PowerShell) 항목이 1개일 때 `Save-ResultJson` 의 items 가 배열이 아니라 객체로 저장됨. 보고서 빈 화면, merge.py TypeError. | 해결(1.3.2): `Save-ResultJson` items 를 `@()` 로 항상 배열(-i W-01 실측 확인) |
| R-11 | 중 | S5 | (pwsh 7) ConvertTo-Json 이 `<` 를 이스케이프하지 않아 증적의 `</script>` 가 report.html 에서 실행될 수 있음. PS 5.1 은 해당 없음. | 해결(1.3.2): result.json 의 `< > &` 를 `<` 등으로 이스케이프(PS 5.1/7 공통) |
| R-12 | 하 | S5 | `New-PrivateDirectory` 가 ACL 제한에 실패해도 경고만 하고 진행. | 해결(1.3.2): ACL 제한·chmod 실패 시 예외로 중단, run.ps1(02/03/07)은 exit 2 |

### 1-2. 01_unix

| ID | 심각도 | 기준 | 내용 | 상태 |
|---|---|---|---|---|
| U-R1 | 상 | S6 | 비 root 실행 시 읽지 못한 설정을 "설정 없음"으로 보고 GOOD/NA. 예: vsftpd.conf 0600 → U-35, named.conf → U-51, snmpd.conf → U-60/61, /root/.bashrc → U-14. hidepid=2 에서는 서비스 항목 전부 GOOD. | 해결(1.3.2): root 가 아니면 GOOD/NA 를 ERROR("확인 못 함")로 일괄 변환(`nonroot_unverified`, 03_web 동일) |
| U-R2 | 상 | S6 | U-17/U-20 `-perm -0022` 는 "그룹과 기타 모두 쓰기"만 잡음. 0664/0646 이 GOOD. | 해결(1.3.2): `-perm -0020 -o -perm -0002`(하나라도 쓰기면 위반), U-17 fix 동일 |
| U-R3 | 상 | S6 | U-28 방화벽: nft 규칙셋이 비어 있지만 않으면 GOOD(정책 accept 여도), iptables INPUT 규칙 1개(ACCEPT all 포함)여도 GOOD. | 해결(1.3.2): nft 는 input 훅 체인의 policy drop/drop·reject 규칙, iptables 는 `-S INPUT` 의 DROP 정책/DROP·REJECT 규칙만 제한으로 인정 |
| U-R4 | 상 | LOGIC | U-03 주석 처리된 `#auth ... pam_tally2.so deny=5` 를 설정으로 셈. faillock.conf 만 있고 PAM 스택에 모듈이 없어도 GOOD. | 해결(1.3.2): 주석 줄 제외, PAM 스택에 모듈이 있을 때만 faillock.conf deny 인정(fix 도 모듈 없으면 ERROR) |
| U-R5 | 상 | LOGIC | U-50/U-51 이 include 만 있는 Debian `/etc/bind/named.conf` 를 고르고 include 를 따라가지 않음. 주석·여러 줄 블록 미처리. | 해결(1.3.2): `named_conf_flatten`(include·주석·여러 줄 블록·view/zone 문맥), 존별 allow-transfer 판정, fix 도 include 파일 대상 |
| U-R6 | 상 | S6 | U-34/36/44/52/54 가 `/etc/inetd.conf`·`*.socket` 유닛을 보지 않음. 연결 전에는 프로세스가 없는 inetd/소켓 기동 서비스가 GOOD. | 해결(1.3.2): `check_service_disabled` 4번째 인자로 inetd.conf 활성 줄 확인, 소켓 유닛 추가(finger/tftp.socket), fix `fix_inetd_disable` |
| U-R7 | 중 | LOGIC | U-12 `TMOUT=0`(해제)이 GOOD. `export TMOUT=600` 형태를 인식하지 못해 MANUAL. | 해결(1.3.2): TMOUT=0 VULN, 따옴표·export/readonly/typeset 형태 인식 |
| U-R8 | 중 | LOGIC | U-06 `pam_wheel.so trust` 만 있어도 GOOD(제한이 아니라 무암호 통과). `deny` 미고려. | 해결(1.3.2): required/requisite + deny 없음만 제한으로 인정, fix 는 기본 예시의 trust/deny 줄을 풀지 않음 |
| U-R9 | 중 | LOGIC | U-14 `export PATH=".:$PATH"` 의 따옴표 때문에 "." 를 인식 못 함. | 해결(1.3.2): 따옴표·주석 제거, 파일의 모든 PATH= 줄 검사(fix 동일) |
| U-R10 | 중 | S6 | U-15/23/25 가 `-xdev` 로 제외한 별도 파일시스템(/home, /var)이 있어도 GOOD(detail 에만 기재). find 실패·시간 제한 없음. | 해결(1.3.2): `scan_find` - / + 별도 로컬 파일시스템 각각 -xdev, SCAN_TIMEOUT(900초), 시간 초과·find 오류(rc≥2)는 ERROR. 원격 FS 는 미검색(detail 기재) |
| U-R11 | 중 | S6 | U-67 이 /var/log 최상위 30개 파일만 검사하고, 소유자·권한을 못 읽으면 건너뜀. | 해결(1.3.2): 하위 포함 전체 파일을 POSIX find 조건으로 검사, 시간 초과·실패 ERROR. fix 도 같은 조건(-perm -0133 오류 수정, 권한을 넓히지 않음) |
| U-R12 | 중 | S6 | U-02 pwquality.conf 가 없으면 PASS_MAX_DAYS 만으로 GOOD. | 해결(1.3.2): 복잡성(minlen)을 항상 판정 - pwquality.conf(.d)·PAM minlen= 인자. 한계: pam_pwquality 가 스택에 있는지는 미확인 |
| U-R13 | 중 | LOGIC | U-13 login.defs 가 SHA512 면 shadow 의 남은 `$1$` 해시를 보지 않음. 증적에 해시 앞 6자 노출(S5). | 해결(1.3.2): 설정과 /etc/shadow 해시를 모두 판정, 증적은 계정명:알고리즘 식별자만. fix 는 취약 해시 계정이 있으면 ERROR(비밀번호 재설정 안내) |
| U-R14 | 중 | LOGIC/S2 | U-27 소유자 비교 누락, `host +` 형태 누락, 홈 stat 시 autofs/NFS 확인 없음. | 해결(1.3.2): 소유자 비교(hosts.equiv=root, .rhosts=root/해당 계정), 어느 필드든 "+" 검출, 원격·autofs 홈 건너뜀(MANUAL), stat run_to |
| U-R15 | 중 | LOGIC | U-35 Samba `guest ok` 를 마지막 값 하나만 봄. U-40 exports.d·호스트 생략 미처리. U-56 ftpusers 를 접근 제어로 오인. U-57 userlist_deny 미확인. U-59~61 `*6`·include 미처리. U-30 /etc/profile·bashrc 우선순위. | 해결(1.3.2): U-35 전 섹션 guest ok/public, U-40 exports.d·호스트 생략, U-56 ftpusers 불인정(IP 제어 없으면 MANUAL, fix 는 안내만), U-57 userlist_enable/deny, U-59~61 `*6`·includeFile/includeDir(`snmpd_conf_lines`), U-30 login.defs→profile→profile.d→bashrc 순 마지막 값 + 비트 비교 |
| U-R16 | 중 | LOGIC | `check_service_disabled` 가 is-active 만 확인. enabled 상태(재부팅 시 기동)여도 지금 꺼져 있으면 GOOD. | 해결(1.3.2): is-enabled(enabled/enabled-runtime/indirect)도 활성으로 판정. 픽스처 없음(테스트 이미지에 systemd 없음) |
| U-R17 | 하 | LOGIC | U-62 배포판 기본 issue/motd 를 경고문으로 인정. U-65 timesyncd 미인식(거짓 VULN). U-47 postfix 기본값 미인정(거짓 VULN). U-11 `/usr/bin/false` VULN. U-01 sshd 미설치 시 telnet root 로그인 미확인. | 해결(1.3.2): U-62 배포판 기본 문구 제외(`banner_custom_lines`, 휴리스틱), U-65 timesyncd 인식(NTP= 미지정 시 MANUAL), U-47 defer_unauth_destination 인정, U-11 `*/false`, U-01 Linux telnet(securetty/pam_securetty) 확인 |
| U-R18 | 하 | S1 | U-28 `iptables -L` 이 legacy 환경에서 커널 모듈을 자동 로드할 수 있음. | 해결(1.3.2): legacy iptables 는 ip_tables 모듈이 이미 적재된 경우(/proc/net/ip_tables_names)에만 조회. nft 조회의 모듈 자동 적재는 미조치 |

### 1-3. 02_windows · 07_pc

| ID | 심각도 | 기준 | 내용 | 상태 |
|---|---|---|---|---|
| W-R1 | 상 | S6 | W-12 가 RSOP(GPO)만 봄. 로컬 정책으로 켠 익명 SID/이름 변환이 GOOD. secedit `LSAAnonymousNameLookup` 으로 판정해야 함. | 해결(1.3.2): secedit `[System Access] LSAAnonymousNameLookup` 으로 판정, 값 없으면 ERROR |
| W-R2 | 상 | S6 | W-16/PC-04 `Get-SmbShareAccess` 실패(권한 등)가 "Everyone 없음"=GOOD. W-17 `Get-SmbShare` 실패도 GOOD. | 해결(1.3.2): 공유/접근 권한 조회 실패 → ERROR(W-16/PC-04), W-17 은 AutoShareServer=0 + 목록 실패 시 ERROR, Everyone 은 S-1-1-0 현지화 이름으로 비교 |
| W-R3 | 상 | S6 | W-22 FTP 경로의 환경변수(`%SystemDrive%`)를 펼치지 않아 Get-Acl 이 항상 실패 → GOOD. W-43/W-58 도 ACL 조회 실패를 GOOD 으로 처리. | 해결(1.3.2): W-22 경로 환경변수 전개, W-22/43/58 ACL·목록 조회 실패 → ERROR, Everyone 은 SID(S-1-1-0) |
| W-R4 | 상 | S6 | W-64/PC-15 방화벽 조회가 로컬 저장소 기준(GPO 로 끈 상태 미반영 가능). PC-15 는 꺼진 타사 방화벽도 "활성"으로 봄. | 해결(1.3.2): `Get-NetFirewallProfile -PolicyStore ActiveStore`, PC-15 타사 방화벽은 productState 활성 비트 확인, 조회 실패는 ERROR |
| W-R5 | 상 | LOGIC | W-23 FTP 익명 인증을 잘못된 설정 경로에서 읽음(사이트 단위 설정 미검출). | 해결(1.3.2, IIS 실기 미검증): FTP 사이트별 `sites/site[@name]/ftpServer/...` + siteDefaults 로 판정. 별건: SMB 대체 판정의 `RestrictNullSessAccess` 실제 위치(LanmanServer\Parameters)도 읽도록 수정 - fixes/W-23 은 여전히 Lsa·IIS:\ 경로에 써서 조치가 반영되지 않음(조치 담당 확인 필요) |
| W-R6 | 중 | LOGIC | W-40 auditpol `/r` 의 Inclusion Setting 값이 지역화되어 한글판에서 항상 VULN(실측 필요). | 해결(1.3.2): `auditpol /backup` CSV 의 GUID·숫자 설정 값을 열 위치로 판정(한글판 실측: /backup 머리글도 번역됨 확인), 개인 임시 폴더·60초 제한 |
| W-R7 | 중 | S6/S1 | secedit 종료 코드 미확인(부분 내보내기 시 W-49 거짓 VULN 등), 임시 파일 경로가 예측 가능(SYSTEM 실행 시 C:\Windows\Temp 선점 공격으로 정책 값 위조 → 거짓 GOOD). | 해결(1.3.2): `New-PrivateTempFile`(무작위 이름·전용 ACL 폴더), 종료 코드·시간 초과·필수 섹션 확인 실패 시 SecEditFailed |
| W-R8 | 중 | LOGIC | W-08 잠금 임계값 0·`LockoutDuration=-1` 처리 오류. | 해결(1.3.2): LockoutBadCount=0 → VULN, LockoutDuration=-1 → 60분 이상으로 간주 |
| W-R9 | 중 | S6 | W-14/W-06 `Get-LocalGroupMember` 를 영문 그룹명으로 호출. 비영문 OS·고아 SID 오류가 W-14 에서 NA. | 해결(1.3.2): `Get-LocalGroupMembersBySid`(SID 조회 + 고아 SID 시 ADSI 대체), W-14 그룹 부재만 NA·조회 실패는 ERROR |
| W-R10 | 중 | LOGIC | W-28/W-36/PC-18 이 GPO 정책 키(`Policies\...\Terminal Services`)를 보지 않음. | 해결(1.3.2): W-28/W-36/PC-18 이 GPO 키를 먼저 읽고 없을 때 로컬 값 사용 |
| W-R11 | 중 | LOGIC | PC-13/14, W-39 Defender 수동 모드(타사 백신)를 VULN 으로 판정. 서버 OS 에는 SecurityCenter2 가 없음. | 해결(1.3.2): Defender AMRunningMode 수동/EDR 모드·꺼짐 시 SecurityCenter2 타사 백신(활성 비트) 기준 MANUAL, 서버 OS(SC2 없음)는 W-39 MANUAL / PC-13·14 ERROR |
| W-R12 | 중 | LOGIC | PC-06 "설치" 기준인데 실행 중 프로세스만 확인. | 해결(1.3.2): 제거 목록(HKLM 64/32, 로드된 HKU)·사용자별 설치 폴더 확인 추가. 한계: 로그온하지 않은 사용자 하이브는 미확인(하이브 로드 = 시스템 변경) |
| W-R13 | 중 | S5 | `Protect-SecretText` 가 `--password x`, `-pX`, `/rp`, `curl -u u:p`, `net user id pw` 를 놓침(W-37/W-62). | 해결(1.3.2): `--password`·`--password=`·`-pX`(mysql 류)·`/rp`·`curl -u`·URL 자격증명·`net user id pw`·`net use \\s pw` 마스킹, 단위 호출로 확인 |
| W-R14 | 하 | S6 | `Test-IsDomainController` 조회 실패를 `$false` 로 캐시(DC 에서 W-16 이 SYSVOL 을 VULN 으로). W-60/W-63 CIM 실패가 NA. `Test-RegistryValue` 가 권한 거부와 값 없음을 구분 못 함. | 해결(1.3.2): DC 판별은 CIM→레지스트리 ProductType 대체, 둘 다 실패 시 IsDcUnknown(W-16 SYSVOL/NETLOGON MANUAL). W-60/63 CIM 실패 → ERROR. `Test-RegistryValue` 권한 거부 등은 RegistryQueryFailed → run.ps1 이 GOOD/VULN 을 ERROR |
| W-R15 | 하 | S1/LOGIC | W-33 리다이렉트를 따라가 외부로 요청이 나갈 수 있음. W-61/PC-07 ReFS 를 VULN. W-34 한글판 tlntadmn. W-11/49/46 이름 기반 비교. W-06 그룹 구성원 1명을 GOOD. | 해결(1.3.2): W-33 HttpWebRequest(리디렉션·프록시 미사용), W-61/PC-07 ReFS 양호·FS 미확인 ERROR, W-34 값 기반 해석(해석 불가 MANUAL), W-11/49/46 SID 비교, W-06 구성원이 그룹이면 MANUAL |
| W-R16 | 하 | S2 | secedit·auditpol·bcdedit·Get-HotFix·CDXML cmdlet 에 시간 제한 없음, SID→이름 변환이 DC 연결 불가 시 대기. | 해결(1.3.2): `Invoke-NativeCommand`(secedit 120초·auditpol/bcdedit 60초·tlntadmn 30초), CDXML 은 `Invoke-CimCmdletWithTimeout`(-AsJob), Get-HotFix → CIM(30초), SID→이름은 로컬에서 풀리는 SID 만 변환. 한계: Get-LocalGroupMember/ADSI 의 도메인 구성원 이름 해석은 시간 제한 없음 |

### 1-4. 03_web

| ID | 심각도 | 기준 | 내용 | 상태 |
|---|---|---|---|---|
| WEB-R1 | 상 | S6 | **Debian/Ubuntu Apache 에서 Include 를 하나도 따라가지 못함**(ServerRoot 주석 → 루트를 /etc 로 계산). mods-enabled·sites-enabled 누락으로 WEB-04/05/12/17/18/19 거짓 GOOD. CI 는 httpd:2.4 만 써서 미검출. | 해결(1.3.2): ServerRoot 미지정 시 메인 설정 폴더(conf/ 안이면 상위) 기준, 소문자·디렉터리 Include, 순환·상한(깊이 16/파일 512), 로드 순서 스트림(`apache_conf_stream`). Debian 12 apache2 회귀 이미지(`Dockerfile.apache-debian`) 추가 - 수정 전 vuln 픽스처 WEB-04/18 GOOD → 수정 후 VULN |
| WEB-R2 | 상 | S6 | WEB-26 `-perm -0006`(읽기+쓰기 둘 다)만 VULN — 644 로그 GOOD. WEB-14 10진 권한 비교(R-03). | 해결(1.3.2): WEB-26 기타 권한 비트 하나라도(파일 `-perm -0001/-0002/-0004`, 폴더 자체 포함)면 VULN(가이드 `chmod o-rwx`), 조치도 같은 기준. WEB-14 는 R-03 에서 해결 |
| WEB-R3 | 상 | S6 | 설정 파일·tomcat_home 을 못 찾으면 검사할 파일이 없어 GOOD(WEB-01 "관리자 페이지 미사용" 포함). 비 root 로 읽지 못한 설정도 GOOD/NA. | 해결(1.3.2): 설정·tomcat conf 를 못 찾거나 못 읽으면 그 엔진은 ERROR(`web_load_conf`/`web_load_tomcat_conf`/`web_finish`: VULN > ERROR > MANUAL > GOOD), WEB-01 도 ERROR. 비 root 부분은 `nonroot_unverified` |
| WEB-R4 | 상 | S6 | tomcat_home 이 CATALINA_BASE·RHEL `/usr/share/tomcat`(conf=/etc/tomcat)을 모름, Debian 은 BASE 대신 HOME 선택. | 해결(1.3.2): `tomcat_home` = 실행 중 Bootstrap 의 `-Dcatalina.base=` → CATALINA_BASE/HOME → /var/lib/tomcatN(BASE) → /usr/share/tomcat(RHEL) 순, conf/ 있는 곳만. `tomcat_conf_dir` 는 /etc/tomcat* 대체 경로 |
| WEB-R5 | 중 | LOGIC | `run.sh -e` 가 각 check 의 `detect_web_engines` 에 덮어써져 무시됨. | 해결(1.3.2): `detect_web_engines` 는 WEB_ENGINES 가 비었을 때만 탐지, `-e` 값 검증(apache/nginx/tomcat, 콤마 목록) |
| WEB-R6 | 중 | S6 | nginx 상대경로 include 를 작업 디렉터리 기준으로 해석. Apache 디렉터리 Include·소문자 include 누락, Include 순환 시 무한 재귀(S2). | 해결(1.3.2): nginx 상대 include 는 nginx.conf 폴더 기준, 한 줄 여러 지시자·주석 처리, Apache 디렉터리/소문자 Include, 같은 파일 한 번만+깊이·개수 상한(S2) |
| WEB-R7 | 중 | S6 | IIS WEB-10/11/12/14/15/19/26 이 조회 실패 시 `IisConfigQueryFailed` 를 세우지 않고 GOOD(WEB-13 은 거짓 VULN). `Get-IisSiteNames` 실패가 "사이트 없음=NA". | 해결(1.3.2, IIS 실기 미검증): WEB-10/12/13/14/15/18/19/26 조회 실패 시 IisConfigQueryFailed, `Get-IisSiteNames`/`Get-IisSitePhysicalPath` 실패 표시 → run.ps1 이 NA/GOOD 을 ERROR. 비관리자+IIS 설치(레지스트리)면 GOOD/NA → ERROR |
| WEB-R8 | 중 | S6 | IIS 가 사이트 루트만 검사(하위 application/virtual directory 의 web.config, 앱 풀 미검사). WEB-09 관리자 계정 SpecificUser 를 GOOD. WEB-16 사이트별 재정의 무시. | 해결(1.3.2, IIS 실기 미검증): `Get-IisSiteConfigPaths` 로 application/vdir 열거 → WEB-04/18/22 경로별, WEB-09 전 application 의 앱 풀 + SpecificUser(Administrators 직접 구성원 VULN, 그 외 MANUAL), WEB-16 사이트별 재정의. 한계: 일반 하위 폴더의 web.config 는 미열거 |
| WEB-R9 | 중 | S5 | Tomcat `<Connector ... keystorePass="...">` 행이 증적에 원문 저장(WEB-08/10/16). | 해결(1.3.2): Tomcat XML 증적의 *Pass/*Password/*secret 속성 값을 `web_mask_xml_secrets` 로 가림(WEB-06/08/10/12/16/17). tomcat 픽스처에 keystorePass 를 넣어 결과물·run_safety 에서 원문 부재 확인 |
| WEB-R10 | 중 | LOGIC | WEB-08 주석 속 maxPostSize, `-1`/`LimitRequestBody 0`(무제한)을 GOOD. WEB-04/12/19 `Options All` 미인식, WEB-12 Options 미지정 기본값. WEB-11 DocumentRoot 범위, WEB-21 리다이렉트 대상 미확인. WEB-09 Tomcat 이 아닌 java 프로세스로 판정. | 해결(1.3.2): WEB-08 주석 제거·`LimitRequestBody 0`/`client_max_body_size 0`/음수 maxPostSize=VULN, WEB-04/12/19 `Options All`(+IncludesNOEXEC), WEB-12 Options 미지정=기본 FollowSymLinks, WEB-11 모든 로드 설정의 DocumentRoot/root, WEB-21 대상 https:// 만, WEB-09 Tomcat 은 Bootstrap java 만. 남음: 조치의 `apache_options_enabled/disable`(lib, 범위 밖)이 `All`·IncludesNOEXEC 를 몰라 그 경우 조치 후 재검증 실패→원복 |
| WEB-R11 | 하 | LOGIC | WEB-13 context.xml 미확인, WEB-05 Tomcat 주석 미제거로 항상 MANUAL, WEB-02 여러 줄 `<user>`, WEB-16 마지막 값 우선, WEB-03 tomcat9 소유자 거짓 VULN, WEB-26 RHEL 로그 경로, 미지원 엔진(JEUS 등)이 NA. | 해결(1.3.2): WEB-13 context.xml 포함(조치도 동일), WEB-05 주석 제거 후 cgi 매핑, WEB-02 여러 줄 `<user>`, WEB-16 로드 순서상 마지막 ServerTokens(조치도 동일, nginx on/build 도 VULN), WEB-03 배포판·실행 계정 소유자 허용, WEB-26 RHEL·설정 로그 경로, JEUS/WebtoB 감지 시 대상 항목 GOOD/NA→MANUAL(run.sh) |
| WEB-R12 | 하 | S4 | IIS WEB-12 가 큰 디렉터리를 전부 메모리에 올림, `proc_pids_by_comm` 프로세스마다 fork. | 일부 해결(1.3.2): `proc_pids_by_comm`/`proc_uid` 셸 내장 read 로(프로세스당 fork 제거). IIS WEB-12 부분은 IIS 담당 |

### 1-5. 08_dbms · 05_network

| ID | 심각도 | 기준 | 내용 | 상태 |
|---|---|---|---|---|
| D-R1 | 상 | S6 | **원격 접속 모드(`--host`/`-SqlHost`)에서 파일·프로세스·레지스트리 기반 항목이 실행한 PC 를 진단**함(PG D-10/D-14, Oracle D-08/10/12/14/15, MySQL D-14, D-07, MSSQL D-10/D-13). | 해결(1.3.2): `db_is_remote`/`db_remote_skip`(sh), `Test-MssqlRemoteTarget`(ps1) - 원격이면 해당 항목 MANUAL "원격 모드 - DB 서버 호스트에서 실행 필요" |
| D-R2 | 상 | S6 | sh(MySQL/PG)에 접속 계정 권한 사전 확인이 없음. 비관리자 계정은 information_schema 에 자기 행만 보여 D-11 이 GOOD. MSSQL 은 sysadmin 확인 쿼리 실패 시 sysadmin 으로 간주. | 해결(1.3.2): `db_privilege_check`/`db_privilege_apply`(MySQL mysql.user 읽기, PG rolsuper·pg_read_all_settings) → 해당 항목 ERROR, MySQL D-04/D-11 은 권한 테이블 직접 조회, MSSQL 확인 실패=비 sysadmin. 권한 없는 계정 회귀 테스트(lowpriv) 추가 |
| D-R3 | 상 | S6 | PG D-10 이 읽지 못한 pg_hba.conf 를 "규칙 없음"=GOOD. 정규식이 database/user 열의 `all` 에 걸려 거짓 VULN, `0.0.0.0 0.0.0.0` 형식·include 누락. | 해결(1.3.2): 읽기 실패 ERROR, 주소 열(4번째)로 판정·주소+마스크 형식 인식, include 있으면 MANUAL |
| D-R4 | 상 | S5 | 05_network N-17 이 `snmp-server` 줄(community 평문·user auth 키) 원문을 증적에 저장. N-01/06/08/09 가 VTY/AUX 블록 전체(평문 password, type 7) 저장. | 해결(1.3.2): `parsers/cisco_ios.py` `mask_secrets` 를 각 check + run.py(전 항목 detail/evidence)에 이중 적용, edge 픽스처로 비밀값 14종 미노출 검사 |
| D-R5 | 중 | S6 | Oracle 비밀번호를 빠뜨리면 조용히 `/ as sysdba`(로컬)로 접속. CDB$ROOT 접속 시 PDB 객체 미조회. 사용자 정의 프로파일 미확인(D-03/05/09). | 해결(1.3.2): --user/--host 에 DB_PASSWORD 없으면 시작 전 중단, CDB$ROOT+PDB 존재 시 계정·객체 항목 GOOD→MANUAL, `oracle_profile_limits`(OPEN 계정이 쓰는 모든 프로파일, 'DEFAULT' 값 해석) |
| D-R6 | 중 | LOGIC | Oracle D-08/10/12/15 가 `#` 주석 줄을 설정으로 인정(거짓 GOOD). | 해결(1.3.2): `oracle_conf_active`(주석 제거·읽기 실패 ERROR) |
| D-R7 | 중 | LOGIC | PG D-08 이미 md5 로 저장된 role 미확인, PG D-11/D-20 접속 DB 하나만 봄, MySQL D-11 전역·테이블 권한 미확인, MySQL D-01 auth_socket root 를 VULN. | 해결(1.3.2): PG D-08 pg_authid md5 role 확인, PG D-11/D-20 다른 DB 있으면 GOOD→MANUAL(`postgres_other_dbs_manual`), MySQL D-11 mysql.user/db/tables_priv 직접 조회(와일드카드 DB 포함), D-01 auth_socket/unix_socket 은 SOCKET |
| D-R8 | 중 | S5 | MSSQL sqlcmd `-C`(서버 인증서 무조건 신뢰): 원격 SQL 인증 시 중간자에게 비밀번호 노출 가능. | 해결(1.3.2): `-C` 는 로컬 대상 또는 `$env:DB_TRUST_SERVER_CERT=1` 일 때만, 인증서 검증 실패 시 사유 안내(fix.ps1 도 같은 함수라 함께 적용) |
| D-R9 | 중 | S6 | `-e postgresql` 같은 엔진 오타면 preflight 를 건너뛰고 전 항목 NA. | 해결(1.3.2): run.sh 가 mysql/postgres/oracle 외 엔진은 exit 2 |
| D-R10 | 중 | S5 | 05_network 출력 폴더가 비공개(700)가 아니고 PID 접미사 없음. N-19/20 정규식이 view·ipv6 토큰 있는 community 를 놓침, N-01 `any()` 판정·`no login` 미처리. | 해결(1.3.2): 출력 폴더 `<host>_05_<ts>-<PID>` 700 + umask 077, `parse_snmp_community`(view/ipv6 토큰), N-01 all()+`no login`. 단 fixes/N-19·20 은 옛 정규식 그대로(조치 범위 밖)라 view/ipv6 줄은 수동 조치 안내로 나옴 |
| D-R11 | 하 | LOGIC | Oracle D-17 두 번째 쿼리 rc 미확인, D-14 ERROR 무시, D-12 12.1 NA, D-26 Unified Auditing, ORA-28002 경고로 전 항목 ERROR(28001 이면 stdin 을 새 비밀번호로 읽을 여지). MSSQL D-23 value_in_use, D-13 WOW6432Node. N-06 이름 ACL, N-21 alias. | 해결(1.3.2): 전부 반영. 만료 예고 경고는 28002/28011/28098(23ai+) 블록 제거, 28001 은 preflight 1단계(connect 뒤 stdin EOF)에서 중단 - gvenzl 26ai 로 비밀번호 미변경 확인 |
| D-R12 | 하 | S4 | Oracle D-20 `dba_objects` 전체 DISTINCT. | 해결(1.3.2): 사용자별 EXISTS 로 변경 |

---

### 1-6. 진단이 엄격해지며 드러난 조치(fix) 후속 과제

진단은 고쳤지만 대응하는 조치가 새 판정을 따라가지 못하는 항목이다. 조치는 재검증에 실패하면 자동 원복되므로
**시스템을 망가뜨리지는 않는다**. 다만 "조치 실패(원복)"로 끝나므로 수동 조치가 필요하다.

| ID | 내용 | 상태 |
|---|---|---|
| F-R1 | W-23 조치가 Lsa 경로와 존재하지 않는 `IIS:\` FTP 경로에 쓴다. 진단은 `LanmanServer\Parameters`·FTP 사이트 설정을 본다. | 열림 |
| F-R2 | PC-06 진단이 "설치"까지 보게 되어, 프로세스 중지 조치로는 해소되지 않는다. | 열림 |
| F-R3 | IIS WEB-04/18/22(하위 application 설정), WEB-16(사이트별 재정의): 조치가 사이트 루트·서버 전역만 바꾼다. | 열림 |
| F-R4 | WEB-18 Debian: `LoadModule` 만 주석 처리하고 mods-enabled 의 DAV 지시어를 남겨 문법 검사에 실패하고 원복된다. a2dismod 방식(`*-enabled` 링크 제거)이 필요하다. | 열림 |
| F-R5 | `apache_options_disable` 가 `Options All`·IncludesNOEXEC 를 모른다(WEB-04/12/19 조치 원복). 조치가 아직 `$(tomcat_home)/conf` 만 쓴다(/etc/tomcat 배치 미대응). fix_safety 에 Debian Apache 케이스가 없다. | 열림 |
| F-R6 | PG D-08(md5 로 저장된 role), MySQL D-11(전역·테이블 권한), Oracle D-03/05/09(사용자 정의 프로파일): 조치가 새 판정 범위를 다루지 않는다. | 열림 |
| F-R7 | 05_network N-19/N-20 조치가 옛 정규식을 써서, view/ipv6 토큰이 있는 community 는 수동 안내로 나온다. | 열림 |
| F-R8 | U-59~61 조치가 includeFile/includeDir 로 불러온 파일을 고치지 않는다. U-61 은 `rocommunity6 default` 를 다루지 않는다. U-01 이 telnet 때문에 VULN 이면 sshd 만 고치는 U-01 조치는 원복된다(telnet 차단은 U-52). | 열림 |
| F-R9 | U-32 조치가 Debian 의 nologin 시스템 계정 중 홈이 없는 계정(`list` → `/var/list` 등) 때문에 재검증 VULN → 원복되는 것으로 보인다(미확인). | 열림(확인 필요) |

## 2. 검증 환경의 한계 (실기로 확인하지 못한 범위)

| ID | 내용 |
|---|---|
| L-01 | **도메인 컨트롤러**: DC 전용 분기(W-01~03 계정 열거 생략, W-16 SYSVOL 제외, W-32 manual)는 코드 검토만 했다. CI 러너는 재부팅이 필요한 DC 승격을 할 수 없다. |
| L-02 | **한글 Windows**: 러너가 영문(en-US)이라 로캘 의존 출력(W-40 auditpol, W-34 tlntadmn, PC-08 bcdedit)은 한글판에서 실측하지 못했다. |
| L-03 | **Solaris/AIX/HP-UX**: 문서 기준 구현이며 실기 검증 불가(결과마다 "미검증" 문구가 붙음). |
| L-04 | **RHEL 계열·Debian Apache·RHEL Tomcat**: CI 픽스처는 Debian 12(01_unix)와 공식 httpd/nginx/tomcat 이미지만 쓴다. 배포판 패키지 레이아웃(WEB-R1, WEB-R4)은 검증 범위 밖이었다. |
| L-05 | **Oracle**: CI 상시 job 에 없다(로컬 gvenzl 컨테이너로만 검증). |
| L-06 | **PC-14 Defender**: 러너에서 켤 수 없어 조치는 "실패 후 원복" 경로만 확인했다. |
| L-07 | **05_network**: 실제 장비가 아닌 텍스트 픽스처 기반 판정 로직 테스트다. |
| L-08 | **CI 일시 장애**: PowerShell Gallery 다운로드 실패로 static-analysis 가 실패할 수 있다(재실행으로 해결, 코드 문제 아님). |
