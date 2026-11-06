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
| R-11 | 중 | S5 | (pwsh 7) ConvertTo-Json 이 `<` 를 이스케이프하지 않아 증적의 `</script>` 가 report.html 에서 실행될 수 있음. PS 5.1 은 해당 없음. | 재해결(1.4.0): 1.3.2 의 치환이 `'<'→'<'` 로 저장돼 아무것도 바꾸지 않았다(교차검증 X-01). `\u003c` 등으로 고치고 CI 에서 pwsh 7 로 `</script>` 증적을 저장해 확인한다 |
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
| F-R1 | W-23 조치가 Lsa 경로와 존재하지 않는 `IIS:\` FTP 경로에 쓴다. 진단은 `LanmanServer\Parameters`·FTP 사이트 설정을 본다. | 해결(1.3.3): 진단과 같은 대상(LanmanServer·Lsa, FTP 사이트별/siteDefaults 익명 인증). CI 재현 케이스 SMB·FTP 적용 GOOD → 원복 VULN 확인 |
| F-R2 | PC-06 진단이 "설치"까지 보게 되어, 프로세스 중지 조치로는 해소되지 않는다. | 해결(1.3.3): fix 등급 manual(제품별 제거는 업무 판단, 프로세스 종료는 원복 불가) - guide.json deviation, fixes/PC-06.ps1 삭제 |
| F-R3 | IIS WEB-04/18/22(하위 application 설정), WEB-16(사이트별 재정의): 조치가 사이트 루트·서버 전역만 바꾼다. | 해결(1.3.3): `Invoke-FixIisConfigPaths`(진단과 같은 경로 순회), `Invoke-FixIisRemoveServerHeader`(WEB-16·**W-33 도 같은 결함**이었음). IIS 픽스처에 하위 app/vdir·사이트 재정의 재현 추가 |
| F-R4 | WEB-18 Debian: `LoadModule` 만 주석 처리하고 mods-enabled 의 DAV 지시어를 남겨 문법 검사에 실패하고 원복된다. a2dismod 방식(`*-enabled` 링크 제거)이 필요하다. | 해결(1.3.3): mods-enabled 링크 백업 후 제거. 추가로 `sed -i` 가 심볼릭 링크를 일반 파일로 바꿔 원복 후에도 링크가 사라지던 문제(조치 8개 공통)를 `web_sed_inplace` 로 수정 |
| F-R5 | `apache_options_disable` 가 `Options All`·IncludesNOEXEC 를 모른다(WEB-04/12/19 조치 원복). 조치가 아직 `$(tomcat_home)/conf` 만 쓴다(/etc/tomcat 배치 미대응). fix_safety 에 Debian Apache 케이스가 없다. | 해결(1.3.3): All 전개·IncludesNOEXEC, Tomcat 조치 12개가 `tomcat_conf_dir` 사용, fix_safety 에 apache-debian·tomcat·tomcat-etc 추가. WEB-08(0/-1 값 무시), WEB-12(Options 없음을 NA 로 표시)도 수정 |
| F-R6 | PG D-08(md5 로 저장된 role), MySQL D-11(전역·테이블 권한), Oracle D-03/05/09(사용자 정의 프로파일): 조치가 새 판정 범위를 다루지 않는다. | 해결(1.3.3): PG D-08 role 별 승인+운영자 입력, MySQL D-11 DB·테이블 권한 회수(원복 가능, 전역 권한은 수동 안내), Oracle 사용자 정의 프로파일. 새 상태 PARTIAL/MANUAL(원복 없이 수동 필요 보고). **PG D-08 원복이 원래부터 항상 실패**(ALTER SYSTEM 을 트랜잭션 블록으로 보냄)하던 것도 수정 |
| F-R7 | 05_network N-19/N-20 조치가 옛 정규식을 써서, view/ipv6 토큰이 있는 community 는 수동 안내로 나온다. | 해결(1.3.3): `parse_snmp_community` 재사용(N-18 포함), view/ipv6 ACL 유지한 채 재발급 |
| F-R8 | U-59~61 조치가 includeFile/includeDir 로 불러온 파일을 고치지 않는다. U-61 은 `rocommunity6 default` 를 다루지 않는다. U-01 이 telnet 때문에 VULN 이면 sshd 만 고치는 U-01 조치는 원복된다(telnet 차단은 U-52). | 해결(1.3.3): include 파일까지 조치(`snmpd_conf_files`), `*6`·`com2sec -Cn` 처리, changes.log 에 community 원문 미기록. U-01 은 telnet 원인이면 변경 없이 SKIPPED("U-52 먼저") |
| F-R9 | U-32 조치가 Debian 의 nologin 시스템 계정 중 홈이 없는 계정(`list` → `/var/list` 등) 때문에 재검증 VULN → 원복되는 것으로 보인다(미확인). | 해결(1.3.3): 재현됨. 조치 대상을 진단과 같은 기준으로, nologin 계정 홈은 root:root 755 로 생성(서비스 계정에 쓰기 공간을 주지 않음) |

### 1-7. 실검증 테스트 교차검증 — 2026-10-28 (1.3.3)

독립 리뷰어가 run/fix 안전 테스트 자체를 검토해 **실제 문제를 놓치고 통과(거짓 PASS)하는 경로 16건**을 찾았다. 모두
고친 뒤, 일부러 문제를 넣어(음성 대조) 테스트가 실제로 FAIL 하는지 확인했다.

| ID | 심각도 | 내용 | 상태 |
|---|---|---|---|
| T-01 | 상 | 01_unix fix_safety 원복 비교가 8개 파일뿐 - 실제로 `/etc/issue.net`(U-62 백업 없이 덮어씀)·`/etc/gshadow`(U-09 미백업)가 원복 후 달랐는데 PASS | 해결: 파일시스템 전체(경로·종류·권한·소유자·크기)+내용 해시, U-62·U-09 백업 추가 |
| T-02 | 상 | 01_unix·03_web fix-apply 가 "APPLIED 1건 이상"만 확인 - FAILED_NOT_ROLLED_BACK 도 PASS. 실제로 U-13·U-15·U-65 가 원복되고 있었음 | 해결: 기대 APPLIED/SKIPPED 집합 고정. **U-15 는 백업 사본을 재검증이 다시 찾아 항상 원복**되던 실제 버그(소유자 메타 백업으로 변경), U-13·U-65 는 변경 없음을 SKIPPED 로 |
| T-03 | 상 | 08_dbms 에 진단 실행 검수(run_safety) 자체가 없었음 | 해결: 연결 + DB 서버 상태(전역 변수·계정·권한·pg_settings·hba) 진단 전후 비교 |
| T-04 | 상 | Windows S5 에 심은 비밀값 3개 중 진단이 실제 읽는 것은 1개(W-37) - 07·IIS·MSSQL 은 빈 검사 | 해결: 카테고리별로 진단이 읽는 위치에 심고 양성 대조(evidence 에 마스킹 형태 확인) |
| T-05 | 중 | S6 가 root VULN 항목만 비교, 비 root 결과 누락·시간 초과도 PASS | 해결: 비 root GOOD/NA 0건·항목 집합 동일·NR_RC=124 FAIL. 원격 DB 는 `--nr-same` |
| T-06 | 중 | 프로세스 비교가 이름만, 새 프로세스만, 컨테이너에 데몬 없음 | 해결: PID+명령행 양방향, 상주 프로세스 배치 |
| T-07 | 중 | S5 검색 범위가 root 출력 폴더뿐, 원문 형태만 | 해결: stdout/stderr·비 root 출력 포함, JSON·HTML 이스케이프 해제 후 검색 |
| T-08 | 중 | SQL 읽기 전용 판정이 `/* */ DROP`, `SELECT INTO`, `pg_reload_conf()`, CTE DML 등을 통과, PG 여러 줄 문장 누락 | 해결: 주석·리터럴 제거 후 판정, 부작용 함수 denylist, csvlog 파싱 |
| T-09 | 중 | 08 preflight 실패 시 판정된 항목, lowpriv 의 D-01/08/11 외 항목을 보지 않음 | 해결: 허용목록 외 판정 FAIL, 26항목 전부 비교 |
| T-10 | 중 | 03_web fix_safety 가 주 설정 파일 하나 cksum, apache-debian·tomcat 미대상 | 해결: 설정 트리 전체(링크 대상 포함), 6개 케이스 |
| T-11 | 중 | Windows fix_safety 가 적용 0건이면 PASS, 원복 확인이 판정 비교뿐 | 해결: 최소 적용 건수·auto 항목 APPLIED 강제, 실제 상태 스냅샷 비교 |
| T-12 | 중·하 | Windows 스냅샷: 사라진 서비스 미탐지, secedit/sqlcmd 조회 실패 시 빈 값끼리 같음 | 해결: 양방향 비교, 조회 실패 FAIL, 레지스트리·방화벽·TEMP 범위 확대 |
| T-13 | 하·중 | Unix S1 이 /tmp 하위·/dev/shm·sysctl·mounts 를 보지 않음 | 해결: 추가(비 root 실행 후도 비교) |
| T-14 | 중 | S2 제한 900초, 응답 없는 외부 명령 재현 없음 | 해결: 무응답 가짜 명령(HANG_CMDS) 케이스 180초 상한 - **실제 무기한 대기 6곳 발견**(U-45 postconf/exim, U-48·U-62 postconf, U-49 named -v, U-66 systemctl, 공통 `sshd -T`) → `run_to` 로 감쌈 |
| T-15 | 하 | 비밀값이 모두 영숫자라 이스케이프 형태 누락을 검증 못 함 | 해결: 특수문자 섞은 비밀값 추가 |
| T-16 | 하 | MySQL 테스트 이미지에 `diff` 없음 - 전후 비교가 빈 결과로 PASS 가능 | 해결: Dockerfile 에 diffutils 등 추가 |

보강된 테스트가 새로 잡아낸 실제 결함(위 표 외):
- 03_web WEB-10(ProxyPass/proxy_pass)·WEB-21(Redirect) 증적에 URL 속 비밀번호·토큰 원문이 남음(S5) → `web_mask_url_secrets`.
- IIS 조치 원복이 열거형 속성(`httpErrors@errorMode` 등)을 되돌리지 못하면서 "원복 완료"로 보고(WEB-22) → 값 정규화 + 원복 후 재조회 확인.
- Windows secedit 조치·원복이 %TEMP% 에 `.jfm` 찌꺼기를 남김 → 전용 임시 폴더째 삭제.

### 1-8. 현 상태 교차검증과 전 항목 양방향 판정 검증 — 2026-10-29~30 (1.4.0)

독립 에이전트가 KNOWN_ISSUES 를 보기 전에 코드만으로 v1.3.3 을 평가했고, 실제 결함 9건(X-01~X-09)을 찾았다. 아울러
v1.3.3 까지는 항목 대부분이 한 상태로만 테스트돼(Windows 2/64, PC 2/18, DBMS 1/26 만 GOOD·VULN 양방향) check 가
항상 같은 값을 돌려주도록 망가져도 테스트가 잡지 못했다. 1.4.0 에서 **모든 (카테고리, 엔진, 항목)을 취약 상태와 양호
상태로 각각 세팅해 판정을 확인**하도록 바꿨다.
- 커버리지 판정기 `lib/tests/coverage.py --strict`: 421개(카테고리×엔진×항목) 중 양방향 264, 사유 있는 면제 157, 누락 0.
  - 면제 사유는 `manual-by-design`(정책·인적 판단), `na-for-engine`(가이드 대상 아님), `env-unavailable`(아래 L-xx)
    세 가지로 제한된다(`lib/tests/coverage_exempt.json`).
- 항목별 케이스(`tests/fixtures/cases/`)는 상태를 세팅한 뒤 다시 읽어 확인한다. 선언된 케이스가 하나라도 실행되지 않으면
  FAIL 이다. VULN 케이스는 조치 적용 → 재진단 GOOD → 원복 → 상태 동일까지 확인한다.
- 기대값은 가이드 판단기준에서 정한다. 도구 출력으로 기대값을 만들던 `-Bootstrap` 은 차이 출력 전용으로 바꿨다(X-08).
- 음성 대조: 케이스 준비 단계 무력화, check 강제 GOOD, secedit 캐시 무효화 제거 — 모두 FAIL 하는 것을 확인했다.

**교차검증 결함(X)**

| ID | 심각도 | 내용 | 상태 |
|---|---|---|---|
| X-01 | 중 | R-11 수정이 실제로는 아무것도 바꾸지 않았다(위 R-11 참고). | 해결(1.4.0) |
| X-02 | 상 | 보안정책(secedit) 캐시를 비우지 않아, 조치 후 재검증이 이전 값을 읽었다. 실제로 적용됐는데 원복되거나, 연속 조치에서 오판했다(02/07). | 해결: `Clear-SecEditCache`, 연속 조치 회귀 케이스 |
| X-03 | 중 | N-08 이 `transport input ssh telnet` 을 놓쳐 거짓 양호였다. 조치도 같은 정규식을 썼다. | 해결: 토큰 단위 `vty_allows_telnet` |
| X-04 | 상 | fix.sh 가 조치를 같은 셸에서 실행했다. 조치 도중 셸이 죽으면 원복·기록 없이 반쯤 바뀐 상태로 남았다. | 해결: `run_fix_isolated` |
| X-05 | 중 | merge.py 가 BOM 이 있는 Windows result.json 을 건너뛰었다. | 해결: utf-8-sig, `lib/tests/merge_test.py` |
| X-06 | 상 | fix 가 result.json 의 호스트·카테고리를 확인하지 않아, 다른 서버의 결과로도 조치했다. | 해결: 불일치 시 exit 2(`--force`), 7일 경과 시 확인 |
| X-07 | 중 | U-01 이 문법 검사를 생략하고 APPLIED 로 남는 경로가 있었다. 01_unix 조치 21곳이 `sed -i` 로 심볼릭 링크를 깼다. | 해결: SKIPPED/ERROR, `fix_sed_inplace`, CI 금지 검사 |
| X-08 | 상 | Windows·IIS·MSSQL 기대값을 도구 자신의 출력에서 만들어, 오판이 정답으로 고정됐다. | 해결: 위 양방향 검증 |
| X-09 | 중 | fix.ps1 재검증에 run.ps1 의 조회 실패 → ERROR 변환이 없었다. | 해결(02/07) |

**양방향 검증이 새로 잡아낸 판정·조치 결함**(모두 수정, 재현 케이스 추가)

| 영역 | ID | 내용 |
|---|---|---|
| 05_network | N-R1 | N-07 이 `exec-timeout` 의 초를 버려 `0 0`(무제한)을 양호로, 초를 생략한 줄을 미설정으로 판정 |
| | N-R2 | N-10 이 배너가 있으면 항상 MANUAL — 경고 문구·시스템 정보 노출로 판정 |
| | N-R3 | N-22 가 ACL 의 인터페이스 적용 여부를 보지 않아 양호 판정 불가 |
| | N-R4 | N-31 명시적 `ip directed-broadcast` 가 MANUAL 로 남음 → 취약(조치 추가) |
| 01_unix | U-C1 | `pgrep/pkill -f` 가 명령줄 전체를 봐 무관한 프로세스로 거짓 취약, 조치가 무관한 프로세스를 종료 |
| | U-C2 | U-42 가 프로세스를 먼저 종료하고 상태를 기록해 원복 시 서비스가 기동되지 않음 |
| | U-C3 | U-65/66 이 enable 상태를 기록하지 않아 원복 후에도 켜진 채로 남음 |
| | U-C4 | `fix_service_disable` 이 유닛 종류 없는 이름에 항상 실패 — 서비스 조치 다수가 아무것도 못 끄고 원복 |
| | U-C5 | U-47 이 주석 처리된 설정을 취약으로 판정 |
| 03_web | WEB-C1 | WEB-05 CGI 를 켜면 항상 MANUAL → 실행 디렉터리 제한 여부로 판정 |
| | WEB-C2 | WEB-11 Tomcat 항상 MANUAL → appBase 위치로 판정 |
| | WEB-C3 | WEB-13 `<Resources>`·`<ResourceLink>` 를 DB 리소스로 셈 |
| | WEB-C4 | WEB-06/12 조치가 context.xml `allowLinking` 을 남겨 항상 원복 |
| | WEB-C5 | WEB-08 Nginx `client_max_body_size 0` 조치 분기 없음 |
| | WEB-C6 | WEB-02 Tomcat CredentialHandler 해시를 양호로 인정하지 않음 |
| | C-WEB07 | IIS 경로 삭제 실패를 무시하고 APPLIED, 원복이 폴더를 중첩 복사 |
| | C-WEB09 | IIS 앱 풀 identityType 을 항상 빈 값으로 읽어 조치·원복이 무동작 |
| 08_dbms | D-C1 | Oracle D-01 이 정상 서버도 영구 취약 → `DBA_USERS_WITH_DEFPWD` 기준(deviation) |
| | D-C2 | Oracle D-12 조치 NA 기준이 check 와 어긋남 |
| | D-C3 | MySQL D-07 조치 후 재기동이 항상 실패(datadir 소유자) |
| | D-C4 | PostgreSQL D-26 원복 후 설정 재적재 없음 |
| | D-C5·C6 | Oracle D-19/26 원복이 미지정 파라미터를 SET, PFILE 사본 복사 실패로 항상 "일부 실패" |
| | D-C7 | `oracle_query` 탭 패딩으로 조치 SQL 이 깨짐 |
| | D-C8 | Oracle REVOKE 실패를 무시하고 APPLIED |
| | C-D01 | MSSQL D-01 취약 판정 경로가 없었음 → 서버 안 PWDCOMPARE(일치 여부만, 해시 미저장) |
| | C-D23·D24 | MSSQL 확장 프로시저를 `sys.objects` 에서 찾아 0건 — D-24 취약 불가, D-23 항상 MANUAL → `sys.all_objects` |
| 02_windows·07_pc | F-W18 | `Get-ServiceChecked` 가 표시 이름까지 찾아 "Browser" 를 커널 드라이버 bowser 로 오인 — W-18 이 항상 취약 |
| | F-W14 | 구성원 1명일 때 `.Count` 가 `$null` 이라 항상 취약 |
| | F-W21 | FTP 가 구동 중이면 SSL 필수 설정과 무관하게 취약 |
| | F-W24 | 존재하지 않는 속성(denyByDefault)을 읽어 IP 제한을 설정해도 항상 취약 |
| | F-W01 | 관리자 이름 변경 직후 WMI 조회가 비어 ERROR |
| | F-W20 | NetBIOS 조치가 엉뚱한 레지스트리 위치에 써서 효과 없음 |
| | F-W25 | DNS 영역 전송 조치가 실제로 바뀌지 않는데 APPLIED |
| | F-W41 | 서비스 상태를 백업하지 않아 원복 후에도 W32Time 이 구동 상태 |
| | F-W42 | `Limit-EventLog` 가 Server 2025 에서 크기를 바꾸지 못함 → EventLogConfiguration API |
| | F-W17·PC-04 | Server 2025 가 기본 공유 삭제를 거부하는데 "즉시 제거"로 보고 → Server 서비스 재시작, 실패는 ERROR |
| | F-W39·PC-13 | 서명 업데이트는 원복 불가인데 고지 없음 → `Register-FixNoRollback` |

**케이스 하네스 교차검증(거짓 PASS 경로)** — 독립 리뷰어가 새 하네스를 코드로 검토했다. 선언된 케이스가 조용히 빠지거나
판정 비교를 건너뛰는 경로는 없었다. 아래는 조치 검증·준비 확인이 암묵적으로 생략되던 경로다.

| ID | 심각도 | 내용 | 상태 |
|---|---|---|---|
| H-01 | 중 | coverage 게이트가 CI 에 없었다 | 해결: static-analysis 에서 `--strict` |
| H-02 | 중 | 03_web: fix 등급이 auto/confirm 인데 조치 스크립트가 없으면 조치 검증 없이 PASS(WEB-05 VULN 4건). FIX_MODE 미출력도 PASS. `FIX: NONE` 은 fix.sh 가 아예 돌지 않아도 PASS | 해결: 사유(`# FIX: SKIP`) 없으면 FAIL, FIX_MODE 없음 FAIL, NONE 은 changes.log 기록 필수 |
| H-03 | 하 | 01_unix: 준비 함수 종료 코드(SETUP_RC)를 보지 않았다 | 해결 |
| H-04 | 하 | IIS/MSSQL: 준비 후 기대 상태(Want)가 비면 확인을 통과, 조치 스크립트가 있는데 Fix 도 제외 사유도 없는 케이스를 허용 | 해결: 둘 다 FAIL |
| H-05 | 하 | engine 이 빠진 케이스는 다중 엔진 러너가 실행하지 않는데 coverage 는 첫 엔진으로 셌다(현재 해당 케이스 없음) | 해결: coverage.py 가 FAIL |
| H-06 | 하 | Oracle 케이스는 주간·수동 실행만 돈다 — PR/push 에서 Oracle 판정 회귀가 바로 드러나지 않는다 | 한계(L-05) |
| H-07 | 하 | 원복 동일성 비교 범위: 03_web 은 엔진 설정 트리만, MSSQL 은 Probe 한 줄, 02/07 레지스트리는 check 가 읽는 키만 본다. MySQL 스냅샷에 mysqld 실행 uid 가 없다 | 한계: 현재 조치가 바꾸는 대상은 비교 범위 안에 있다. 범위 밖을 건드리는 조치를 새로 만들면 비교 범위도 넓혀야 한다 |

## 2. 검증 환경의 한계 (실기로 확인하지 못한 범위)

| ID | 내용 |
|---|---|
| L-01 | **도메인 컨트롤러**: DC 전용 분기(W-01~03 계정 열거 생략, W-16 SYSVOL 제외, W-32 manual)는 코드 검토만 했다. CI 러너는 재부팅이 필요한 DC 승격을 할 수 없다. |
| L-02 | **한글 Windows**: 러너가 영문(en-US)이라 로캘 의존 출력(W-40 auditpol, W-34 tlntadmn, PC-08 bcdedit)을 러너에서 실측할 수 없다. 1.5.0 C6: 파싱을 `lib/Common.psm1` 함수(ConvertFrom-AuditPolBackup·Get-BcdEditEntryCount·ConvertFrom-TlntadmnConfig)로 분리하고, 한글 Windows 11 에서 읽기 전용으로 수집한 실제 출력(auditpol /backup·bcdedit /enum, `lib/tests/fixtures/locale/`)으로 단위 테스트한다(`lib/tests/locale_parse_tests.ps1`, CI static-analysis). 남은 것: tlntadmn 한글 출력은 Telnet 서버가 2016 이후 없어 합성 샘플뿐, 진단 전체 흐름(run.ps1)의 한글판 실행은 1.5.0 C7 에서 확인했다: 한글 Windows 11 Home(ko-KR)에서 07_pc 18항목 오류 0, 콘솔 코드페이지 949(bcdedit 머리글 한글)·65001 결과 동일. 한글 Windows Server 의 02_windows 전체 실행은 G-07. |
| L-03 | **Solaris/AIX/HP-UX**: 문서 기준 구현이며 실기 검증 불가(결과마다 "미검증" 문구가 붙음). |
| L-04 | **RHEL Apache/Tomcat 패키지**: 1.5.0 C2 부터 Rocky Linux 9 의 httpd·tomcat 패키지(`apache-rhel`·`tomcat-rhel`)를 전역 vuln/hardened 픽스처, 조치 안전(적용 → 문법 검사 → 원복 동일성, Tomcat 은 조치 후 tomcat 계정이 tomcat-users.xml 을 읽을 수 있는지까지), 진단 실기 안전 검사로 검증한다. 항목별 양방향 케이스와 coverage 집계는 공식 이미지·Debian 기준만 있다(rhel 은 재현 층). RHEL 본체·SELinux enforcing 은 여전히 밖. 01_unix 의 rhel 계열 OS 는 Rocky Linux 9 케이스로 검증한다(1.5.0 C1). |
| L-05 | **Oracle**: 1.4.0 부터 CI `oracle` job(주간 스케줄·수동 실행, gvenzl/oracle-free 26ai 다이제스트 고정)에서 22항목 양방향 케이스·조치·원복을 돈다 - 매 push 에는 돌지 않는다(이미지 약 2.8GB). 남은 한계: ① D-12(리스너 비밀번호)는 12.2 이상에서 NA(가이드 명시)라 취약/양호 분기(12.1 이하 listener.ora)를 실기로 만들 수 없다(coverage 면제 env-unavailable) ② D-07 취약(Oracle 을 root 로 구동)은 Oracle 이 root 기동을 거부해 root 소유 `ora_pmon_*` 모의 프로세스로 check 의 /proc 판정 경로만 검증한다. |
| L-06 | **PC-14 Defender**: 러너에서 켤 수 없어 조치는 "실패 후 원복" 경로만 확인했다. |
| L-07 | **05_network**: 실제 장비가 아닌 텍스트 픽스처 기반 판정 로직 테스트다. |
| L-08 | **CI 일시 장애**: PowerShell Gallery 다운로드 실패로 static-analysis 가 실패할 수 있다(재실행으로 해결, 코드 문제 아님). |
| L-09 | **MSSQL D-08**: SHA-256 미만 비밀번호 해시는 SQL Server 2012 미만에서만 생긴다. 러너 LocalDB·Express(2022)에서 만들 수 없어 양호 방향만 검증한다. 정식 인스턴스는 1.5.0 C4 부터 CI `mssql-express`(SQL Server 2022 Express, 주간·수동)로 LocalDB 와 같은 검사를 돈다. |
| L-10 | **W-34 Telnet 서버**: Windows Server 2016 이상에는 Telnet 서버가 없다(지원 OS 중 2012 R2 만 해당). 러너(Server 2025)에서 구동 상태를 만들 수 없어 미설치 → GOOD 만 검증한다. |
| L-11 | **W-45 백신 미설치**: Defender 제거·서비스 중지에 재부팅이 필요해 러너에서 미설치 상태를 만들 수 없다. 설치 → GOOD 만 검증한다. |

## 3. 검토 필요 사항 (1.4.0 기준, 2026-11-02)

검증된 실행 환경은 README "검증된 실행 환경" 절을 참고한다. 이 절은 그 밖의 부분에서 사람이 판단하거나 확인해야 하는 것을 모은다.

### 3-1. 결정 대기 (유지보수자 판단 필요)

| ID | 대상 | 현재 상태 | 선택지 | 권장 |
|---|---|---|---|---|
| Q-01 | WEB-05 CGI 실행 디렉터리 제한 (Apache/Nginx/Tomcat) | 1.4.0 부터 VULN 판정이 나온다(WEB-C1). guide.json `fix=confirm` 인데 `03_web/fixes/WEB-05.sh` 가 없어 조치 대상에서 조용히 빠진다. 케이스는 `# FIX: SKIP` 사유로 통과시켰다 | ① `fix` 를 manual 로 바꾸고 `deviation` 에 사유 기록(CGI 를 지정 디렉터리로 옮기려면 콘텐츠·URL 이전 필요) ② 조치 스크립트 작성(예: `ScriptAlias` 밖 `ExecCGI` 제거) | ① |
| Q-02 | WEB-17 가상 디렉터리 삭제 | 가이드 기준이 "불필요한" 가상 디렉터리라 Alias/Context 가 있으면 MANUAL, 없으면 GOOD. VULN 은 자동 판정하지 않는다(coverage 면제 manual-by-design). guide.json `fix=auto` 인데 조치 스크립트가 없다(VULN 이 나오지 않아 실행 경로 없음) | ① 면제 유지 + `fix` 를 manual 로 정정, deviation 기록 ② 샘플·문서 경로(`/manual`, `/docs`, `/examples` 등) 같은 알려진 불필요 경로만 VULN 으로 판정 | ② 검토 후 결정. 최소한 `fix` 등급 정정은 필요 |
| Q-03 | WEB-10 불필요한 프록시 (Apache/Nginx/Tomcat, IIS 는 ARR 로 양방향 판정·조치) | ProxyPass/proxy_pass 가 있으면 MANUAL, 없으면 GOOD. VULN 은 자동 판정하지 않는다 | ① 면제 유지 ② `ProxyRequests On` 같은 정방향 오픈 프록시는 업무 필요와 무관하게 위험하니 VULN 으로 판정 | ② |
| Q-04 | WEB-05·WEB-11·WEB-02 판정 범위 확장 | 1.4.0 에서 판정 근거를 넓혔다. WEB-05 는 실행 디렉터리 제한 여부(WEB-C1), WEB-11 Tomcat 은 appBase 위치(WEB-C2), WEB-02 는 Tomcat CredentialHandler 해시를 양호로 인정(WEB-C6). 그런데 guide.json `deviation` 에는 기록하지 않았다 | `deviation` 에 해석 근거 기록(루트 원칙 1) | 기록 |
| Q-05 | 주간 스케줄 범위 | cron(일 03:00 KST)이 oracle job 만이 아니라 전 job 을 돈다 | ① 유지(주간 회귀 겸용) ② oracle 만 돌도록 다른 job 에 `if` 추가 | ① 비용 문제가 없다면 유지 |
| Q-06 | Docker 이미지 태그 고정 | Oracle 만 다이제스트를 고정했다. `debian:12`·`httpd:2.4`·`nginx:latest`·`tomcat:10`·`mysql:8`·`postgres:16` 은 태그가 움직여 CI 결과가 엔진 버전 변화에 영향받는다 | ① 유지(새 버전 회귀를 빨리 발견) ② 다이제스트 고정 + 주기적 갱신 | ① 유지. 실패 시 이미지 버전부터 확인 |

**처리 결과(1.4.1)**

| ID | 상태 | 내용 |
|---|---|---|
| Q-01 | 해결(1.4.1) | 등급은 confirm 을 유지한다. IIS 는 자동 조치가 있고(`fixes/iis/WEB-05.ps1`) guide.json 등급은 항목 단위라, manual 로 내리면 IIS 조치까지 꺼지기 때문이다. Apache/Nginx/Tomcat 이 수동인 사유와 판정 기준(WEB-C1)은 `deviation` 에 기록했다. fix.sh 는 이 항목을 "조치 스크립트 미구현"으로 건너뛰고 로그에 남긴다 |
| Q-02 | 해결(1.4.1) | WEB-17 `fix` 를 auto → manual 로 정정하고 deviation 을 기록했다. 알려진 경로를 VULN 으로 보는 판정은 넣지 않았다. 샘플 경로(`/manual`, Tomcat docs/examples)는 WEB-07 이 이미 VULN 으로 판정하므로 중복이다 |
| Q-03 | 해결(1.4.1) | Apache `ProxyRequests On` → VULN, 조치 `fixes/WEB-10.sh`(confirm, Off 로 변경). apache·apache-debian 에 양방향 케이스를 추가했다(VULN → 조치 → GOOD → 원복 동일). 역방향 프록시는 지금처럼 MANUAL |
| Q-04 | 해결(1.4.1) | WEB-02(C6)·WEB-05(C1)·WEB-11(C2)의 판정 해석을 `deviation` 에 기록했다 |
| Q-05 | 결정: 유지 | 주간 스케줄에서 전 job 을 돌린다(움직이는 이미지 태그의 회귀를 주 1회 확인). test.yml 주석에 반영 |
| Q-06 | 결정: 유지 | 태그는 고정하지 않는다. 대신 linux-integration job 이 실행한 엔진 버전을 job summary 에 표로 남긴다 |

**재발 방지**: `lib/tests/guide_consistency.py` 를 CI static-analysis 에 추가했다.
- guide.json `fix` 등급과 계열별 조치 스크립트가 어긋나면 FAIL 한다.
- 예외 17건은 `lib/tests/fix_exempt.json` 에 사유와 함께 둔다.
  - `no-vuln-path`: check 가 VULN 을 만들지 않는 항목이다. check 코드에 VULN 경로가 없는지 자동으로 확인한다.
  - `engine-manual`: 그 엔진은 자동 조치가 안전하지 않은 항목이다. guide.json `deviation` 기록이 필수다.
- 이 검사로 MSSQL D-01·D-08, Oracle D-07 의 조치가 없는 사유도 찾아 `deviation` 에 기록했다.

### 3-2. 검증 환경 밖 — 실사용 전 확인 권장

코드에는 분기가 있지만 CI 실기 검증을 하지 않은 범위다. 이 환경에서 처음 돌릴 때는 dry-run 과 결과 검토를 먼저 할 것.

| 영역 | 검증한 것 | 검증하지 않은 것 · 위험 | 참고 |
|---|---|---|---|
| 01_unix OS | Debian 12, Rocky Linux 9.8(1.5.0, authselect minimal PAM) | RHEL 본체·Alma, SUSE, SELinux enforcing(컨테이너는 SELinux 비활성). rhel 계열의 전역 vuln/hardened 픽스처 기대값 고정과 coverage 양방향 집계는 Debian 기준만 있다(Rocky 는 같은 케이스 재현 + 전용 케이스) | L-04 |
| 01_unix 상용 Unix | — | Solaris/AIX/HP-UX 7항목은 문서 기준 구현이다(결과에 "미검증" 표기) | L-03 |
| 02_windows OS | Server 2025 Datacenter, Server 2022 Datacenter(1.5.0 C3, 주간·수동 실행), en-US, 워크그룹. 한글 출력 파싱은 실제 샘플 단위 테스트(C6) | Server 2016/2019(2012 R2 포함) 의 레지스트리 기본값·기능 차이, 한글 로캘에서의 진단 전체 실행, 도메인 컨트롤러 분기(W-01~03 열거 생략, W-16, W-32, W-60, W-63) | L-01, L-02, L-10 |
| 07_pc | 서버 OS 위에서 PC 항목 실행, Windows 11 Home 25H2 ko-KR 실 PC 1대 읽기 전용 진단(1.5.0 C7, 판정 18건 독립 대조) | Windows 10, Pro/Enterprise 에디션, 클라이언트에서의 조치 적용(실 PC 라 실행하지 않음). 에디션별 정책 차이와 Defender 실시간 감시(PC-14), 클라이언트 전용 기본값이 서버와 다를 수 있다 | L-06 |
| 03_web | 공식 이미지 Apache/Nginx/Tomcat, Debian apache2, Rocky 9 httpd·tomcat 9 패키지(1.5.0 C2), IIS 10.0 | RHEL 패키지의 항목별 케이스, SELinux enforcing, IIS 의 다른 OS 버전. Tomcat 9/11·Nginx stable 은 1.5.0 C5 CI `engine-matrix`(주간·수동)로 검증 | L-04 |
| 08_dbms MSSQL | LocalDB 2025, SQL Server 2022 Express 정식 인스턴스(1.5.0 C4, 서비스 계정 NT Service\MSSQL$SQLEXPRESS, 혼합 인증, 주간·수동 실행) | Standard/Enterprise 전용 기능(SQL Agent 등), TCP 포트를 연 원격 접속 구성, SQL Server 2019 이하, 2012 미만 해시(D-08) | L-09 |
| 08_dbms Oracle | 26ai Free 단일 인스턴스 | 19c 등 이전 버전, 12.1 이하 리스너 비밀번호(D-12), RAC/ASM. root 구동(D-07 VULN)은 모의 프로세스로만 검증 | L-05 |
| 08_dbms MySQL/PostgreSQL | MySQL 8.4·8.0, PostgreSQL 16·14·18(8.0/14/18 은 1.5.0 C5 CI `engine-matrix`, 주간·수동) | MySQL 5.7, MariaDB(확장 중단), PostgreSQL 15·17 등 matrix 밖 메이저 버전 | — |
| 05_network | IOS 15.2 형식 텍스트 픽스처 | 실장비 `show running-config` 출력. IOS-XE·다른 IOS 버전의 문법·기본값 생략 차이 | L-07 |

### 3-3. 자동 판정 대신 사람이 판단해야 하는 항목

아래 항목은 가이드 판단기준이 조직 정책이나 업무 필요성에 달려 있어 자동으로 VULN/GOOD 을 정하지 않는다(coverage `manual-by-design`).
결과는 MANUAL 이며 근거 목록(계정·파일·설정)을 증적으로 남기므로, 보고서에서 증적을 보고 직접 판정해야 한다.
상세 사유는 `lib/tests/coverage_exempt.json` 의 `note` 를 참고한다.

| 카테고리 | 항목 (수) |
|---|---|
| 01_unix | U-07 U-08 U-23 U-25 U-33 U-45 U-49 U-64 U-66 (9) |
| 02_windows | W-01 W-03 W-06 W-19 W-27 W-35 W-37 W-38 W-47 W-62 (10) |
| 03_web | WEB-02(IIS) WEB-06(Apache·Nginx) WEB-10(Apache·Nginx·Tomcat) WEB-17(Apache·Nginx·Tomcat) WEB-24(IIS) WEB-25(IIS) (6) |
| 05_network | N-02 N-05 N-12 N-14 N-17 N-23 N-24 (7) |
| 07_pc | PC-09 PC-10 PC-11 PC-16 PC-17 (5) |
| 08_dbms | D-02 D-03 D-04 D-06 D-10 D-13 D-20 D-25 D-26 (9, 해당 엔진 기준) |

- 일부 항목은 한 방향만 자동 판정하고 반대 방향은 MANUAL 이다.
  - 취약 방향만 자동 판정: U-66 N-02 N-14 D-03 D-10 D-26
  - 양호 방향만 자동 판정: U-23 U-25 U-45 U-49 W-01 W-06 W-19 W-47 N-17 WEB-10 WEB-17 D-13 D-20
- CI 에서 상태를 만들 수 없어 **한 방향만 검증한 항목**(coverage `env-unavailable`)도 있다. 이 항목들은 실환경 결과를 특히 주의해서 봐야 한다:
  - W-34(Telnet, L-10)
  - W-45(백신 미설치, L-11)
  - W-60·W-63(도메인, L-01)
  - PC-14(Defender, L-06)
  - D-08(MSSQL 구버전 해시, L-09)
  - D-12(Oracle 12.1 이하 리스너, L-05)
- `na-for-engine`: W-26 은 가이드 대상이 Windows NT/2000/2003 이라 2008 이상에서는 NA 다.

### 3-4. 테스트 체계 자체의 한계

- **기대값의 근거**: 케이스의 기대 판정은 가이드 판단기준을 이 저장소가 해석해 정한 것이다.
  - 판정 로직과 기대값을 같은 해석에서 만들었기 때문에, 해석이 틀렸다면 테스트도 같이 틀린다.
  - 가이드 해석이 들어간 항목(3-1 Q-04, guide.json `deviation` 이 있는 항목)은 외부 검토가 필요하다.
- **Oracle 회귀 주기**: Oracle 케이스는 주간·수동 실행만 돈다(H-06). Oracle check·fix 를 고쳤다면 `gh workflow run test.yml` 으로 수동 실행해 확인한다.
- **원복 동일성 비교 범위**: 원복 후 같은지 비교하는 대상은 조치가 바꾸는 범위로 한정된다(H-07). 그 범위 밖을 건드리는 조치를 새로 만들면 비교 범위도 함께 넓혀야 한다.
- **confirm 등급 조치**: CI 는 비대화형 응답 주입이나 가상 터미널(`script`)로 확인 단계를 통과시킨다.
  - 실제 운영자 확인 화면의 문구·흐름은 사람이 따로 점검해야 한다.
  - 특히 업무 영향을 고지하는 문구(F4/F5)가 대상이다.
- **Windows 테스트 실행 위치**: 02/07 케이스·조치 테스트는 레지스트리를 실제로 바꾸므로 CI 러너에서만 돈다. 개발자 PC에서는 재현할 수 없다.
- **변이 검증 범위**(1.5.0 D1): `lib/tests/mutation.py` 는 check 를 "항상 GOOD / 항상 VULN" 으로 바꿨을 때 테스트가 FAIL 하는지만 본다.
  - 판정 일부만 틀리는 변이(조건 하나 반전, 경계값 ±1)는 만들지 않는다 - 그런 회귀는 양방향 케이스의 경계 상태가 있어야 잡힌다.
  - 실패 줄에 나온 항목 코드로 "잡힘"을 센다. 조치 검증 등 다른 이유로 같은 항목이 FAIL 해도 잡힘이다.
  - Windows 계열(02/07, 03 IIS, 08 MSSQL)은 CI `mutation-windows` job 에서만 돈다(레지스트리를 실제로 바꿈).

---

## 4. 실무 적용 검증 — 2026-11-03 (1.4.1 + 1.5.0 C1 기준)

"지금 상태로 고객사 실무 진단에 쓸 수 있는가"를 두 관점으로 따로 평가한 뒤 서로의 지적을 교차 확인했다.
- 현장 진단 수행자 관점: 순정 Docker 이미지(debian:12, rockylinux 9, httpd, nginx, tomcat, mysql, postgres)에서 그대로 실행해 결과를 봤다.
- 안전·정확성 감사자 관점: S1~S7·F1~F6 과 가이드 판단기준을 코드로 대조했다.
- 양쪽이 모두 확인한 것만 남겼고, 유지보수자가 코드를 다시 대조했다(P-01 은 직접 재현).

**결론**: Solaris/AIX/HP-UX(L-03)를 뺀 전 카테고리 "조건부 사용 가능". 진단 결과는 아래 거짓 양호 항목을 수동으로 대조한 뒤 보고서에 쓰고, 조치는 dry-run → 승인 → `-i` 항목별 적용 순서를 지킨다.

| ID | 심각도 | 기준 | 내용 | 상태 |
|---|---|---|---|---|
| P-01 | 상(차단) | S5 | N-17: `snmp-server host <IP> vrf <이름> ...` 줄은 마스킹이 vrf 이름을 가리고 community 원문을 남긴다. raw/N-17.txt·result.json·report.html 에 저장됨(재현 확인) | 해결(1.5.0): 마스킹 패턴에 vrf 추가, edge 픽스처에 vrf 줄 2개 + 비밀값 잔존 검사 |
| P-02 | 상 | S6 | U-04: /etc/passwd 비밀번호 필드가 빈 계정(비밀번호 없이 su 가능)을 GOOD 으로 판정하고, 증적에 "2번째 필드 전부 'x'"라고 남긴다(`length($2) > 0`) | 해결(1.5.0): 빈 필드를 VULN(비밀번호 없음), 조치는 pwconv 로 해소되지 않아 변경 없이 SKIPPED(비밀번호 설정·잠금 안내). 케이스 debian·rhel |
| P-03 | 상 | S6 | U-47/48: Exim 을 보지 않아 Exim 서버를 "메일 서비스 미설치"로 GOOD 판정(U-45/46 은 Exim 확인) | 해결(1.5.0): Exim 이 있으면 relay/VRFY·EXPN ACL 을 증적으로 남기고 MANUAL. 케이스 debian·rhel |
| P-04 | 상 | S6 | WEB-01/02(Tomcat): tomcat-users.xml 의 작은따옴표 속성, `manager-script`·`admin-gui` 등 다른 관리 역할 계정을 놓쳐 GOOD | 해결(1.5.0): lib/common.sh tomcat_admin_user_elems·xml_attr - 관리 역할 manager-gui/script/jmx/status·admin-gui/script, 작은따옴표 속성. 조치도 같은 기준. 케이스 2건 |
| P-05 | 중 | S6 | WEB-22(Nginx): `error_page` 줄이 하나라도 있으면 GOOD - 기본 설정(50x 만 지정)에서도 GOOD 이지만 404 기본 페이지가 그대로 나간다 | 해결(1.5.0): 블록 단위 판정(lib/common.sh nginx_error_page_gaps) - error_page 가 있는 블록마다 404 필요. 조치는 그 블록에 404 추가. 기본 이미지 기대값 GOOD → VULN, 케이스 2건 |
| P-06 | 중 | S6 | Apache/Nginx: 설정 파일을 고정 경로에서만 찾는다. 프로세스 `-f`/`-c` 로 다른 설정을 쓰는 서버는 엉뚱한(또는 미사용) 파일로 판정 | 해결(1.5.0): 실행 중인 httpd/apache2 -f, nginx -c 의 절대 경로 설정 파일을 먼저 쓴다(lib/common.sh _proc_conf_arg) |
| P-07 | 중 | S6 | Tomcat: 실행 중 인스턴스가 여러 개여도 첫 인스턴스만 진단(`tomcat_home`) | 해결(1.5.0): 인스턴스가 여럿이면 run.sh 가 목록·진단 대상을 경고하고, CATALINA_BASE 를 지정하면 그 인스턴스를 진단한다(인스턴스별 재실행). 한 번에 전 인스턴스를 진단하지는 않음 |
| P-08 | 상 | S6 | MySQL D-10: `host='%'` 만 본다. `0.0.0.0/0.0.0.0`, `%.%` 등 전체 허용 호스트를 GOOD | 해결(1.5.0): 모든 호스트 허용 형태('%', '', '%.%', '0.0.0.0/0.0.0.0' 등)를 VULN. 케이스 1건 |
| P-09 | 상 | S6 | PostgreSQL D-01: pg_hba `trust`(비밀번호 없이 접속)를 보지 않고 비밀번호 설정 여부만으로 GOOD | 해결(1.5.0): 비밀번호가 있어도 pg_hba_file_rules 에 postgres/all 대상 trust 규칙이 있으면 MANUAL. 공식 이미지 기본 trust 로 기대값 GOOD → MANUAL, trust 제거 GOOD 케이스 |
| P-10 | 상 | S6 | N-03: `username ... password 0 <평문>` 을 보지 않아 enable secret 만 있으면 GOOD. 증적 마스킹이 일반 단어("또는")까지 가린다 | 해결(1.5.0): service password-encryption 없이 username 평문 password 가 있으면 VULN, 한글 문장은 마스킹하지 않음. 케이스 2건 |
| P-11 | 중 | 판정 | N-01: AAA 기본 목록(`aaa authentication login default ...`)으로 VTY 를 인증하는 장비를 VULN 으로 판정 | 해결(1.5.0): aaa new-model + login default 목록이면 라인 인증으로 인정. 케이스 2건 |
| P-12 | 하 | 판정 | PostgreSQL D-10: 인증 방식 열을 보지 않아 전체 대역 `reject` 규칙도 VULN | 해결(1.5.0): 인증 방식 열이 reject 인 규칙은 제외. 케이스 1건 |
| P-13 | 하 | 판정 | WEB-13(Tomcat): 기본 UserDatabase Realm 만 있어도 항상 VULN | 해결(1.5.0): type 이 org.apache.catalina.UserDatabase 인 Resource 는 DB 연결 정보에서 제외(기본 Tomcat NA). 조치도 같은 기준, 케이스 3건 |
| P-14 | 하 | 판정 | U-01: `PermitRootLogin prohibit-password` 를 MANUAL 로 판정(가이드상 root 직접 접속 허용 = 취약) | 해결(1.5.0): prohibit-password·미설정(기본값)을 VULN, sshd_config 를 읽지 못하면 ERROR. 케이스 debian·rhel |
| P-15 | 상 | F3·F5 | U-40 조치: 전체 공개 공유를 주석 처리만 하고 `exportfs -ra` 를 하지 않아 실제 공유는 열린 채인데 재진단은 GOOD. 공유 차단은 업무 영향이 있는데 auto 등급 | 해결(1.5.0): 조치 후 exportfs -ra 로 즉시 반영, 원복 시 재실행 필요를 고지. 등급 auto → confirm(deviation). 케이스 debian·rhel |
| P-16 | 상 | F3·F5 | U-42/52/54, W-21 조치: 서비스를 즉시 중지·프로세스 종료하는데 auto 등급. U-52 는 텔넷으로 접속한 세션을 끊을 수 있다(SSH 사전 확인 없음) | 해결(1.5.0): U-42/52/54·W-21 등급 auto → confirm(deviation). U-52 는 텔넷 세션(조상 프로세스 telnetd)에서 실행하면 변경하지 않음 |
| P-17 | 중 | F5 | U-65 조치: 서버 설정이 없으면 `pool pool.ntp.org` 를 추가(폐쇄망 부적합) - deviation 기록 없음, auto 등급 | 해결(1.5.0): 등급 auto → confirm, deviation 에 pool.ntp.org 추가 사실과 폐쇄망 주의 기록 |
| P-18 | 중 | F5 | Oracle D-18/D-22 조치: PUBLIC 권한 회수·리소스 제한 즉시 적용(auto). 가이드 영향 문구는 "영향 없음"이나 운영 앱 영향 가능 | 해결(1.5.0): D-18/D-22 등급 auto → confirm(deviation) |
| P-19 | 중 | S7 | 01_unix fix.sh 가 INT/TERM 만 trap - SSH 끊김(HUP) 시 잠금·로그 정리 없이 종료 | 해결(1.5.0): 01/03/08 fix.sh 가 HUP 을 무시 - 끊겨도 진행 중 항목의 재검증·원복까지 끝남 |
| P-20 | 중 | 운영 | Windows 실행 정책(Restricted 기본값)·`Unblock-File` 안내가 문서에 없다 | 해결(1.5.0): README Windows 절에 Unblock-File·Set-ExecutionPolicy -Scope Process 안내 |
| P-21 | 하 | 운영 | sh 진입점 result.csv 에 BOM 이 없어 한글 Excel 에서 깨진다 | 해결(1.5.0): csv_init 이 UTF-8 BOM 을 쓴다 |
| P-22 | 하 | 운영 | merge.py: 같은 호스트 결과 중복 제거 없음, 준수율 반올림(은행가 반올림)이 summary 와 다름 | 해결(1.5.0): merge.py 가 같은 호스트(+카테고리·환경)는 최근 결과만 남기고 경고, 준수율은 summary.txt 와 같은 버림(report.html 도). merge_test 확장 |
| P-23 | 하 | 운영 | 호스트명: 05_network 는 입력 파일명, 08_dbms sh 는 `uname -n` 대체 없음 | 해결(1.5.0): sh 는 host_name(hostname → uname -n → /proc), 05_network 는 설정의 hostname 줄(없으면 파일 이름) |
| P-24 | 하 | 운영 | `-i` 인자 없이 실행 시 비정상 종료, DB preflight 실패 시 종료 코드 0, dry-run 이 바꿀 값을 보여주지 않음, `audit.sh -h` 에 `set -u` 오류 줄 출력. 05 `run.py -i` 코드 검증 없음 | 해결(1.5.0): 값 없는 옵션은 사용법 오류(exit 2), DB 접속 실패는 종료 코드 4(audit.sh 가 구분), audit.sh -h 정리, 05 run.py -i 코드 검증, 조치 파일마다 머리말 `# 변경:` 을 두어 dry-run·적용 전 확인 목록에 바꿀 대상·값 표시(guide_consistency R5 가 누락 검사) |
| P-25 | 하 | S7 | Windows run.ps1 에 중복 실행 잠금이 없다(sh 는 R-06 에서 해결) | 해결(1.5.0): run.ps1 4개가 `Enter-RunLock`(카테고리별 Mutex, 비정상 종료 시 자동 해제)을 잡고 이미 실행 중이면 exit 2. run_safety_windows.ps1 S7 이 잠금 중 두 번째 실행을 확인 |
| P-26 | 하 | 운영 | WEB-22 Apache 조치의 한글 ErrorDocument 문구가 iso-8859-1 로 응답돼 깨진다 | 해결(1.5.0): 인라인 문구를 ASCII(Not Found/Internal Server Error)로 |
| P-27 | 하 | 테스트 | `run_safety_windows.ps1:255` `-Force` 매개변수 오류를 무시하고 진행 | 해결(1.5.0): Remove-WebVirtualDirectory 에 없는 -Force 제거 |

## 5. 기획 대비 허점 — 2026-11-05 (1.6.0 계획)

초기 기획(인프라 자동 진단 + 자동 조치)과 현재 구현을 비교한 결과다. 전제: 주 사용자는 점검 컨설턴트이고 조치도
컨설턴트가 직접 실행한다. 호스트별 실행 + 결과 병합(`lib/merge.py`)으로 충분하며 원격 일괄 실행은 만들지 않는다.
새 환경·벤더 확장 중단(1.2.0)은 유지한다. 1.5.0(C5·C7·D1~D3·D5)을 끝낸 뒤 진행하며, 1.5.0 의 D4(운영 영향표)는 G-02 와 겹쳐 1.6.0 으로 옮긴다.

| ID | 중요도 | 허점 | 계획 | 상태 |
|---|---|---|---|---|
| G-01 | 상 | 무인 조치 불가: confirm 등급(85항목)은 `--yes` 로도 항목마다 y/N 을 묻는다 | `fix --policy <파일> --operator <이름>`. 정책 파일은 jq 없이 sh/PowerShell 이 같은 방식으로 읽는 줄 단위 텍스트(머리말 `category=`·`expires=`·`approver=`, 카테고리별 승인 코드, `[host:이름]` 구역의 `-코드` 제외). 설정값은 가이드 값 고정(정책에서 바꾸지 않음). 카테고리 불일치·유효기간 경과·정책에 없는 호스트(`[host:*]` 없음)면 거부, X-06 유지. 실패 항목은 원복 후 계속, 종료 시 실패 목록 요약(백업 실패 exit 3 만 전체 중단) | 열림 |
| G-02 | 상 | 원복 불가(F4)·업무 중단 가능(F5) 항목이 무인 일괄 적용될 위험 | 정책에 승인돼 있어도 항목별 `:irreversible` 플래그가 있어야 적용. 항목별 분류표(구 D4 운영 영향표)를 함께 작성 | 열림 |
| G-03 | 중 | 감사 로그(F6)에 실제 실행자가 남지 않는다(root·공용 관리자 계정) | 정책 모드에서 실행자·승인자·정책 파일 SHA-256·실행 시각 기록 | 열림 |
| G-04 | 중 | 조치 전·후 비교 산출물이 없다(merge.py 는 호스트 병합만) | `merge.py --diff <전> <후>`: 호스트+코드로 맞춰 조치 완료(VULN→GOOD)·미조치(VULN→VULN)·신규 취약(GOOD/NA→VULN, 맨 위)·확인 필요(MANUAL·ERROR 관련)로 분류 | 열림 |
| G-05 | 중 | MANUAL 46항목은 보고서 밖에서 손으로 판정·편집해야 한다 | 보고서 화면에서 취약/양호 + 사유를 입력해 `manual_verdicts.json` 으로 저장, merge.py 가 최종·비교 보고서에 반영(result.json 은 불변, 자동/사람 판정 구분 표시) | 열림 |
| G-06 | 중 | 05_network 조치가 승인 범위와 무관하게 전 항목 명령어를 생성한다 | 장비 직접 적용은 만들지 않는다(콘솔 붙여넣기). 명령어 생성에 G-01 정책 형식을 적용해 승인 항목만 출력 | 열림 |
| G-07 | 중 | 실제 운영 환경 미검증(§2 L-01·L-02·L-04, 07_pc 클라이언트) | 분석자 PC Hyper-V VM 수동 검증: ① 한글 Windows Server 2022 ② 같은 VM 도메인 컨트롤러 승격 ③ Windows 11(C7 에서 실 PC 읽기 전용 진단 완료 - VM 에서는 조치 적용·원복) ④ RHEL 9 + SELinux enforcing. 결과는 README 검증 환경 표에 "수동 검증"으로 기록. 실점검 증적 회수는 하지 않는다 | 열림 |
| G-08 | 중 | 판정 로직과 테스트 기대값이 같은 가이드 해석에서 나온다(§3-4) | guide.json `deviation` 이 있는 항목을 실무 컨설턴트 1명이 외부 검토 | 열림 |

하지 않기로 한 것: 원격 일괄 실행(SSH/WinRM), 실점검 증적 회수, 네트워크 장비 직접 적용, 엑셀 점검표 양식(HTML·CSV 로 제출).
