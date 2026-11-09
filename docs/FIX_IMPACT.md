# 조치 운영 영향 분류표 (FIX_IMPACT)

> 이 문서는 `python lib/tests/fix_impact.py` 가 조치 파일 머리말과 guide.json 에서 생성한다 - 손으로 고치지 말 것.
> CI(static-analysis)가 `--check` 로 최신인지 확인한다.

- **원복 불가 사유**: 조치 파일 머리말 `# 원복:` (운영 안전 기준 F4 - 백업으로 완전히 되돌릴 수 없음)
- **업무 영향**: 조치 파일 머리말 `# 영향:` (F5 - 적용하는 순간 서비스 중지·세션 끊김·계정 잠금·접근 차단·재시작 등 업무가 끊길 수 있음)
- **:irreversible**: 둘 중 하나라도 있으면 정책 모드(`fix --policy`)에서 정책 파일에 `코드:irreversible` 로 적어야 적용된다(없으면 `POLICY_SKIPPED`). 대화형 실행에는 영향 없음.

전체 조치 187개 중 정책에 `:irreversible` 이 필요한 조치 48개.

## 01 Unix 서버 (58개 조치, :irreversible 필요 16개)

| 코드 | 대상 | 제목 | 등급 | 원복 불가 사유 | 업무 영향 | :irreversible |
|---|---|---|---|---|---|---|
| U-01 | Unix(sh) | root 계정 원격 접속 제한 | confirm | - | - | - |
| U-02 | Unix(sh) | 비밀번호 관리정책 설정 | confirm | - | - | - |
| U-03 | Unix(sh) | 계정 잠금 임계값 설정 | confirm | - | - | - |
| U-04 | Unix(sh) | 비밀번호 파일 보호 | confirm | - | - | - |
| U-05 | Unix(sh) | root 이외의 UID가 ‘0’ 금지 | confirm | - | root 외 UID 0 계정의 UID 즉시 변경 — 그 계정으로 하던 관리 작업·서비스가 root 권한을 잃음(홈 밖 파일은 이전 UID 소유로 남음) | 필요 |
| U-06 | Unix(sh) | 사용자 계정 su 기능 제한 | confirm | - | - | - |
| U-09 | Unix(sh) | 계정이 존재하지 않는 GID 금지 | auto | - | - | - |
| U-10 | Unix(sh) | 동일한 UID 금지 | confirm | - | 중복 UID 계정의 UID 즉시 변경 — 그 계정이 쓰던 홈 밖 파일·실행 중 작업의 접근 권한이 끊길 수 있음 | 필요 |
| U-11 | Unix(sh) | 사용자 shell 점검 | auto | - | 시스템 계정 쉘을 nologin 으로 변경 — 이 계정으로 로그인하거나 su(-s 없이)로 쓰던 작업이 실패 | 필요 |
| U-12 | Unix(sh) | 세션 종료 시간 설정 | confirm | - | - | - |
| U-13 | Unix(sh) | 안전한 비밀번호 암호화 알고리즘 사용 | auto | - | - | - |
| U-14 | Unix(sh) | root 홈, 패스 디렉터리 권한 및 패스 설정 | auto | - | - | - |
| U-15 | Unix(sh) | 파일 및 디렉터리 소유자 설정 | auto | - | - | - |
| U-16 | Unix(sh) | /etc/passwd 파일 소유자 및 권한 설정 | auto | - | - | - |
| U-17 | Unix(sh) | 시스템 시작 스크립트 권한 설정 | auto | - | - | - |
| U-18 | Unix(sh) | /etc/shadow 파일 소유자 및 권한 설정 | auto | - | - | - |
| U-19 | Unix(sh) | /etc/hosts 파일 소유자 및 권한 설정 | confirm | - | - | - |
| U-20 | Unix(sh) | /etc/(x)inetd.conf 파일 소유자 및 권한 설정 | auto | - | - | - |
| U-21 | Unix(sh) | /etc/(r)syslog.conf 파일 소유자 및 권한 설정 | auto | - | - | - |
| U-22 | Unix(sh) | /etc/services 파일 소유자 및 권한 설정 | auto | - | - | - |
| U-24 | Unix(sh) | 사용자, 시스템 환경변수 파일 소유자 및 권한 설정 | auto | - | - | - |
| U-26 | Unix(sh) | /dev에 존재하지 않는 device 파일 점검 | auto | - | - | - |
| U-27 | Unix(sh) | $HOME/.rhosts, hosts.equiv 사용 금지 | auto | - | - | - |
| U-29 | Unix(sh) | hosts.lpd 파일 소유자 및 권한 설정 | auto | - | - | - |
| U-30 | Unix(sh) | UMASK 설정 관리 | auto | - | - | - |
| U-31 | Unix(sh) | 홈디렉토리 소유자 및 권한 설정 | auto | - | - | - |
| U-32 | Unix(sh) | 홈 디렉토리로 지정한 디렉토리의 존재 관리 | auto | - | - | - |
| U-34 | Unix(sh) | Finger 서비스 비활성화 | auto | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 finger 서비스 중지(fingerd 종료·xinetd 재적용) — finger 조회 끊김 | 필요 |
| U-35 | Unix(sh) | 공유 서비스에 대한 익명 접근 제한 설정 | auto | - | - | - |
| U-36 | Unix(sh) | r 계열 서비스 비활성화 | auto | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 rlogin/rsh/rexec 서비스 중지·데몬 종료 — r 계열 원격 접속 세션·스크립트 끊김 | 필요 |
| U-37 | Unix(sh) | crontab 설정파일 권한 설정 미흡 | confirm | - | - | - |
| U-38 | Unix(sh) | DoS 공격에 취약한 서비스 비활성화 | auto | - | xinetd 재적용(reload/restart)으로 echo·discard·daytime·chargen 서비스 중지 — 이를 쓰던 점검·모니터링 끊김 | 필요 |
| U-39 | Unix(sh) | 불필요한 NFS 서비스 비활성화 | confirm | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 NFS 서버 서비스 중지·nfsd 종료 — 이 서버의 NFS 공유를 마운트한 클라이언트 접근 끊김 | 필요 |
| U-40 | Unix(sh) | NFS 접근 통제 | confirm | - | 전체 공개 공유 줄 주석 후 exportfs -ra 로 즉시 반영 — 그 공유를 쓰던 NFS 클라이언트 접근 끊김 | 필요 |
| U-41 | Unix(sh) | 불필요한 automountd 제거 | confirm | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 autofs 중지·automount 종료 — 자동 마운트된 원격 파일시스템 접근 끊김 | 필요 |
| U-42 | Unix(sh) | 불필요한 RPC 서비스 비활성화 | confirm | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 RPC 서비스(rpc.cmsd·rstatd·rquotad 등) 중지·프로세스 종료 — 해당 RPC 를 쓰던 클라이언트 끊김 | 필요 |
| U-43 | Unix(sh) | NIS, NIS+ 점검 | confirm | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 NIS(ypserv·ypbind) 중지 — NIS 로 계정·호스트를 조회하던 로그인·이름 해석 실패 | 필요 |
| U-44 | Unix(sh) | tftp, talk 서비스 비활성화 | auto | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 tftp·talk 서비스 중지·프로세스 종료 — tftp 전송(네트워크 부팅·장비 설정 백업 등) 끊김 | 필요 |
| U-46 | Unix(sh) | 일반 사용자의 메일 서비스 실행 방지 | auto | - | - | - |
| U-47 | Unix(sh) | 스팸 메일 릴레이 제한 | confirm | - | - | - |
| U-48 | Unix(sh) | expn, vrfy 명령어 제한 | auto | - | - | - |
| U-50 | Unix(sh) | DNS ZoneTransfer 설정 | confirm | - | - | - |
| U-51 | Unix(sh) | DNS 서비스의 취약한 동적 업데이트 설정 금지 | confirm | - | - | - |
| U-52 | Unix(sh) | Telnet 서비스 비활성화 | confirm | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 telnet 서비스 중지·telnetd 종료 — 텔넷 사용자 접속 끊김 | 필요 |
| U-53 | Unix(sh) | FTP 서비스 정보 노출 제한 | auto | - | - | - |
| U-54 | Unix(sh) | 암호화되지 않는 FTP 서비스 비활성화 | confirm | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 vsftpd·proftpd 서비스 중지·프로세스 종료 — FTP 사용자 접속·전송 끊김 | 필요 |
| U-55 | Unix(sh) | FTP 계정 shell 제한 | auto | - | ftp 계정 쉘을 nologin 으로 변경 — 이 계정으로 로그인하거나 su(-s 없이)로 쓰던 작업이 실패 | 필요 |
| U-56 | Unix(sh) | FTP 서비스 접근 제어 설정 | confirm | - | - | - |
| U-57 | Unix(sh) | Ftpusers 파일 설정 | confirm | - | - | - |
| U-58 | Unix(sh) | 불필요한 SNMP 서비스 구동 점검 | confirm | 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음 | 실행 중인 snmpd 중지·프로세스 종료 — SNMP 모니터링 수집 끊김 | 필요 |
| U-59 | Unix(sh) | 안전한 SNMP 버전 사용 | confirm | - | - | - |
| U-60 | Unix(sh) | SNMP Community String 복잡성 설정 | confirm | - | - | - |
| U-61 | Unix(sh) | SNMP Access Control 설정 | confirm | - | - | - |
| U-62 | Unix(sh) | 로그인 시 경고 메시지 설정 | auto | - | - | - |
| U-63 | Unix(sh) | sudo 명령어 접근 관리 | auto | - | - | - |
| U-65 | Unix(sh) | NTP 및 시각 동기화 설정 | confirm | - | - | - |
| U-66 | Unix(sh) | 정책에 따른 시스템 로깅 설정 | confirm | - | - | - |
| U-67 | Unix(sh) | 로그 디렉터리 소유자 및 권한 설정 | confirm | - | - | - |

## 02 Windows 서버 (48개 조치, :irreversible 필요 13개)

| 코드 | 대상 | 제목 | 등급 | 원복 불가 사유 | 업무 영향 | :irreversible |
|---|---|---|---|---|---|---|
| W-02 | Windows | Guest 계정 비활성화 | auto | - | - | - |
| W-04 | Windows | 계정 잠금 임계값 설정 | confirm | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| W-05 | Windows | 해독 가능한 암호화를 사용하여 암호 저장 해제 | auto | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| W-07 | Windows | Everyone 사용 권한을 익명 사용자에 적용 | confirm | - | - | - |
| W-08 | Windows | 계정 잠금 기간 설정 | auto | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| W-09 | Windows | 비밀번호 관리 정책 설정 | confirm | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| W-10 | Windows | 마지막 사용자 이름 표시 안 함 | auto | - | - | - |
| W-11 | Windows | 로컬 로그온 허용 | confirm | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| W-13 | Windows | 콘솔 로그온 시 로컬 계정에서 빈 암호 사용 제한 | auto | - | - | - |
| W-15 | Windows | 사용자 개인키 사용 시 암호 입력 | auto | - | - | - |
| W-16 | Windows | 공유 권한 및 사용자 그룹 설정 | confirm | - | - | - |
| W-17 | Windows | 하드디스크 기본 공유 제거 | confirm | 일부 — 레지스트리는 되돌리지만 중지한 기본 공유는 Server 서비스 재시작/재부팅 후에야 다시 생김(실행 중 삭제가 거부되면 조치가 Server 서비스를 재시작 - SMB 연결 끊김) | - | 필요 |
| W-18 | Windows | 불필요한 서비스 제거 | confirm | - | - | - |
| W-20 | Windows | NetBIOS 바인딩 서비스 구동 점검 | confirm | - | - | - |
| W-21 | Windows | 암호화되지 않는 FTP 서비스 비활성화 | confirm | - | - | - |
| W-22 | Windows | FTP 디렉토리 접근권한 설정 | auto | - | - | - |
| W-23 | Windows | 공유 서비스에 대한 익명 접근 제한 설정 | confirm | - | - | - |
| W-25 | Windows | DNS Zone Transfer 설정 | confirm | 불가 — DNS 영역 전송 설정(WMI)은 자동 원복 경로 없음(변경 전 값은 changes.log) | - | 필요 |
| W-28 | Windows | 터미널 서비스 암호화 수준 설정 | confirm | - | - | - |
| W-29 | Windows | 불필요한 SNMP 서비스 구동 점검 | confirm | - | - | - |
| W-30 | Windows | SNMP Community String 복잡성 설정 | confirm | - | - | - |
| W-31 | Windows | SNMP Access Control 설정 | confirm | - | - | - |
| W-32 | Windows | DNS 서비스 구동 점검 | manual | - | - | - |
| W-33 | Windows | HTTP/FTP/SMTP 배너 차단 | auto | - | - | - |
| W-34 | Windows | Telnet 서비스 비활성화 | auto | 불가 — Telnet 인증 방식(tlntadmn)은 자동 원복 경로 없음 | - | 필요 |
| W-36 | Windows | 원격터미널 접속 타임아웃 설정 | auto | - | - | - |
| W-39 | Windows | 백신 프로그램 업데이트 | auto | 불가 — 백신 서명 업데이트는 되돌리지 않는다(이전 서명으로 되돌릴 이유·경로가 없음, 운영 안전 기준 F4 로 사전 고지) | - | 필요 |
| W-40 | Windows | 정책에 따른 시스템 로깅 설정 | auto | 불가 — 감사 정책(auditpol)은 자동 원복 경로 없음(변경 전 값은 changes.log) | - | 필요 |
| W-41 | Windows | NTP 및 시각 동기화 설정 | confirm | - | - | - |
| W-42 | Windows | 이벤트 로그 관리 설정 | auto | 불가 — 이벤트 로그 최대 크기는 자동 원복 경로 없음(변경 전 값은 changes.log) | - | 필요 |
| W-43 | Windows | 이벤트 로그 파일 접근 통제 설정 | auto | - | - | - |
| W-44 | Windows | 원격으로 액세스할 수 있는 레지스트리 경로 | confirm | - | - | - |
| W-46 | Windows | SAM 파일 접근 통제 설정 | auto | - | - | - |
| W-48 | Windows | 로그온하지 않고 시스템 종료 허용 | auto | - | - | - |
| W-49 | Windows | 원격 시스템에서 강제로 시스템 종료 | auto | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| W-50 | Windows | 보안 감사를 로그 할 수 없는 경우 즉시 시스템 종료 | auto | - | - | - |
| W-51 | Windows | SAM 계정과 공유의 익명 열거 허용 안 함 | confirm | - | - | - |
| W-52 | Windows | Autologon 기능 제어 | confirm | - | - | - |
| W-53 | Windows | 이동식 미디어 포맷 및 꺼내기 허용 | auto | - | - | - |
| W-54 | Windows | Dos 공격 방어 레지스트리 설정 | confirm | - | - | - |
| W-55 | Windows | 사용자가 프린터 드라이버를 설치할 수 없게 함 | auto | - | - | - |
| W-56 | Windows | SMB 세션 중단 관리 설정 | auto | - | - | - |
| W-57 | Windows | 로그온 시 경고 메시지 설정 | auto | - | - | - |
| W-58 | Windows | 사용자별 홈 디렉터리 권한 설정 | auto | - | - | - |
| W-59 | Windows | LAN Manager 인증 수준 | confirm | - | - | - |
| W-60 | Windows | 보안 채널 데이터 디지털 암호화 또는 서명 | confirm | - | - | - |
| W-63 | Windows | 도메인 컨트롤러-사용자의 시간 동기화 | auto | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| W-64 | Windows | 윈도우 방화벽 설정 | confirm | - | - | - |

## 03 웹 서비스 (36개 조치, :irreversible 필요 3개)

| 코드 | 대상 | 제목 | 등급 | 원복 불가 사유 | 업무 영향 | :irreversible |
|---|---|---|---|---|---|---|
| WEB-01 | Apache/Nginx/Tomcat(sh) | Default 관리자 계정명 변경 | auto | - | - | - |
| WEB-02 | Apache/Nginx/Tomcat(sh) | 취약한 비밀번호 사용 제한 | confirm | - | - | - |
| WEB-03 | Apache/Nginx/Tomcat(sh) | 비밀번호 파일 권한 관리 | confirm | - | - | - |
| WEB-04 | Apache/Nginx/Tomcat(sh) | 웹 서비스 디렉터리 리스팅 방지 설정 | auto | - | - | - |
| WEB-06 | Apache/Nginx/Tomcat(sh) | 웹 서비스 상위 디렉터리 접근 제한 설정 | confirm | - | - | - |
| WEB-07 | Apache/Nginx/Tomcat(sh) | 웹 서비스 경로 내 불필요한 파일 제거 | confirm | - | - | - |
| WEB-08 | Apache/Nginx/Tomcat(sh) | 웹 서비스 파일 업로드 및 다운로드 용량 제한 | confirm | - | - | - |
| WEB-09 | Apache/Nginx/Tomcat(sh) | 웹 서비스 프로세스 권한 제한 | confirm | - | Apache/Nginx 실행 계정 변경 후 graceful/reload 로 즉시 적용 — 새 계정이 읽을 수 없는 문서·로그·소켓이 있으면 웹 서비스 오류 | 필요 |
| WEB-10 | Apache/Nginx/Tomcat(sh) | 불필요한 프록시 설정 제한 | confirm | - | - | - |
| WEB-12 | Apache/Nginx/Tomcat(sh) | 웹 서비스 링크 사용 금지 | confirm | - | - | - |
| WEB-13 | Apache/Nginx/Tomcat(sh) | 웹 서비스 설정 파일 노출 제한 | confirm | - | - | - |
| WEB-14 | Apache/Nginx/Tomcat(sh) | 웹 서비스 경로 내 파일의 접근 통제 | auto | - | - | - |
| WEB-16 | Apache/Nginx/Tomcat(sh) | 웹 서비스 헤더 정보 노출 제한 | auto | - | - | - |
| WEB-18 | Apache/Nginx/Tomcat(sh) | 웹 서비스 WebDAV 비활성화 | auto | - | - | - |
| WEB-19 | Apache/Nginx/Tomcat(sh) | 웹 서비스 SSI(Server Side Includes) 사용 제한 | auto | - | - | - |
| WEB-21 | Apache/Nginx/Tomcat(sh) | HTTP 리디렉션 | confirm | - | - | - |
| WEB-22 | Apache/Nginx/Tomcat(sh) | 에러 페이지 관리 | auto | - | - | - |
| WEB-23 | Apache/Nginx/Tomcat(sh) | LDAP 알고리즘 적절하게 구성 | confirm | - | - | - |
| WEB-26 | Apache/Nginx/Tomcat(sh) | 로그 디렉터리 및 파일 권한 설정 | auto | - | - | - |
| WEB-03 | IIS | 비밀번호 파일 권한 관리 | confirm | - | - | - |
| WEB-04 | IIS | 웹 서비스 디렉터리 리스팅 방지 설정 | auto | - | - | - |
| WEB-05 | IIS | 지정하지 않은 CGI/ISAPI 실행 제한 | confirm | - | - | - |
| WEB-06 | IIS | 웹 서비스 상위 디렉터리 접근 제한 설정 | confirm | - | - | - |
| WEB-07 | IIS | 웹 서비스 경로 내 불필요한 파일 제거 | confirm | - | - | - |
| WEB-08 | IIS | 웹 서비스 파일 업로드 및 다운로드 용량 제한 | confirm | - | - | - |
| WEB-09 | IIS | 웹 서비스 프로세스 권한 제한 | confirm | - | - | - |
| WEB-10 | IIS | 불필요한 프록시 설정 제한 | confirm | - | - | - |
| WEB-12 | IIS | 웹 서비스 링크 사용 금지 | confirm | - | - | - |
| WEB-13 | IIS | 웹 서비스 설정 파일 노출 제한 | confirm | 불가 — hiddenSegments 에 추가한 항목은 자동으로 제거하지 않음 | - | 필요 |
| WEB-14 | IIS | 웹 서비스 경로 내 파일의 접근 통제 | auto | - | - | - |
| WEB-16 | IIS | 웹 서비스 헤더 정보 노출 제한 | auto | - | - | - |
| WEB-18 | IIS | 웹 서비스 WebDAV 비활성화 | auto | - | - | - |
| WEB-19 | IIS | 웹 서비스 SSI(Server Side Includes) 사용 제한 | auto | 불가 — 제거한 SSI 핸들러 매핑은 자동으로 다시 등록하지 않음 | - | 필요 |
| WEB-21 | IIS | HTTP 리디렉션 | confirm | - | - | - |
| WEB-22 | IIS | 에러 페이지 관리 | auto | - | - | - |
| WEB-26 | IIS | 로그 디렉터리 및 파일 권한 설정 | auto | - | - | - |

## 07 PC (10개 조치, :irreversible 필요 4개)

| 코드 | 대상 | 제목 | 등급 | 원복 불가 사유 | 업무 영향 | :irreversible |
|---|---|---|---|---|---|---|
| PC-01 | PC | 비밀번호의 주기적 변경 | confirm | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| PC-02 | PC | 비밀번호 관리정책 설정 | auto | 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함 | - | 필요 |
| PC-03 | PC | 복구 콘솔에서 자동 로그온을 금지하도록 설정 | auto | - | - | - |
| PC-04 | PC | 공유 폴더 제거 | confirm | 일부 — 레지스트리는 되돌리지만 중지한 기본 공유는 Server 서비스 재시작/재부팅 후에야 다시 생김(실행 중 삭제가 거부되면 조치가 Server 서비스를 재시작 - SMB 연결 끊김) | - | 필요 |
| PC-05 | PC | 항목의 불필요한 서비스 제거 | confirm | - | - | - |
| PC-12 | PC | Windows 자동 로그인 점검 | auto | - | - | - |
| PC-13 | PC | 바이러스 백신 프로그램 설치 및 주기적 업데이트 | auto | 불가 — 백신 서명 업데이트는 되돌리지 않는다(이전 서명으로 되돌릴 이유·경로가 없음, 운영 안전 기준 F4 로 사전 고지) | - | 필요 |
| PC-14 | PC | 바이러스 백신 프로그램에서 제공하는 실시간 감시 기능 활성화 | auto | - | - | - |
| PC-15 | PC | OS에서 제공하는 침입차단 기능 활성화 | confirm | - | - | - |
| PC-18 | PC | 원격 지원을 금지하도록 정책이 설정 | confirm | - | - | - |

## 08 DBMS (35개 조치, :irreversible 필요 12개)

| 코드 | 대상 | 제목 | 등급 | 원복 불가 사유 | 업무 영향 | :irreversible |
|---|---|---|---|---|---|---|
| D-01 | MySQL | 기본 계정의 비밀번호, 정책 등을 변경하여 사용 | confirm | 불가 — 원래 값(빈 비밀번호)으로 되돌리지 않음 | root 계정 비밀번호 즉시 설정 — 빈 비밀번호로 접속하던 앱·스크립트의 새 접속 실패 | 필요 |
| D-03 | MySQL | 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 | confirm | - | default_password_lifetime = 90 즉시 적용 — 비밀번호를 90일 넘게 바꾸지 않은 계정은 바로 만료되어 앱의 새 접속 실패 | 필요 |
| D-07 | MySQL | root 권한으로 서비스 구동 제한 | confirm | 일부 — my.cnf·데이터 파일 소유자는 되돌리지만, root 구동으로 돌아가려면 mysqld 재기동이 필요함 | mysqld 재기동 — 재기동 동안 DB 접속 끊김 | 필요 |
| D-08 | MySQL | 안전한 암호화 알고리즘 사용 | confirm | 불가 — 원래 비밀번호·인증 플러그인으로 되돌릴 수 없음 | 계정 비밀번호·인증 플러그인 즉시 변경 — 기존 비밀번호나 caching_sha2_password 미지원 클라이언트로 접속하던 앱의 새 접속 실패 | 필요 |
| D-11 | MySQL | DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 | confirm | - | - | - |
| D-14 | MySQL | 데이터베이스의 주요 설정 파일, 비밀번호 파일 등과 같은 주요 파일들의 접근 권한이 적절하게 설정 | auto | - | - | - |
| D-21 | MySQL | 인가되지 않은 GRANT OPTION 사용 제한 | confirm | - | - | - |
| D-01 | PostgreSQL | 기본 계정의 비밀번호, 정책 등을 변경하여 사용 | confirm | 불가 — 원래 값(비밀번호 없음)으로 되돌리지 않음 | - | 필요 |
| D-03 | PostgreSQL | 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 | confirm | 일부 — shared_preload_libraries 설정은 되돌리지만, 불러온 passwordcheck 모듈을 내리려면 PostgreSQL 재기동이 필요함 | PostgreSQL 재기동 — 재기동 동안 DB 접속 끊김 | 필요 |
| D-08 | PostgreSQL | 안전한 암호화 알고리즘 사용 | confirm | 일부 — password_encryption 은 되돌리지만, 다시 설정한 role 비밀번호는 원래 값으로 되돌릴 수 없음 | md5 저장 role 의 비밀번호를 새 값으로 재설정 — 기존 비밀번호로 접속하던 앱의 새 접속 실패 | 필요 |
| D-11 | PostgreSQL | DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 | confirm | 불가 — 회수한 권한의 원래 종류를 알 수 없어 다시 부여하지 않음 | - | 필요 |
| D-14 | PostgreSQL | 데이터베이스의 주요 설정 파일, 비밀번호 파일 등과 같은 주요 파일들의 접근 권한이 적절하게 설정 | auto | - | - | - |
| D-26 | PostgreSQL | 데이터베이스의 접근, 변경, 삭제 등의 감사 기록이 기관의 감사 기록 정책에 적합하도록 설정 | confirm | 일부 — postgresql.auto.conf·log_statement 는 되돌리지만(reload 포함) logging_collector 반영에는 재기동이 필요함 | PostgreSQL 재기동 — 재기동 동안 DB 접속 끊김 | 필요 |
| D-01 | Oracle | 기본 계정의 비밀번호, 정책 등을 변경하여 사용 | confirm | 가능 — 잠근 계정을 다시 UNLOCK 함 | 초기 비밀번호 기본 계정 즉시 잠금(ACCOUNT LOCK) — 이 계정으로 접속하던 앱·스크립트 접속 실패 | 필요 |
| D-03 | Oracle | 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 | confirm | - | - | - |
| D-05 | Oracle | 비밀번호 재사용에 대한 제약 설정 | auto | - | - | - |
| D-08 | Oracle | 안전한 암호화 알고리즘 사용 | confirm | - | - | - |
| D-09 | Oracle | 일정 횟수의 로그인 실패 시 이에 대한 잠금정책 설정 | confirm | - | - | - |
| D-11 | Oracle | DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 | confirm | - | - | - |
| D-12 | Oracle | 안전한 리스너 비밀번호 설정 및 사용 | auto | - | - | - |
| D-14 | Oracle | 데이터베이스의 주요 설정 파일, 비밀번호 파일 등과 같은 주요 파일들의 접근 권한이 적절하게 설정 | auto | - | - | - |
| D-15 | Oracle | 관리자 이외의 사용자가 오라클 리스너의 접속을 통해 리스너 로그 및 trace 파일에 대한 변경 제한 | auto | - | - | - |
| D-17 | Oracle | Audit Table은 데이터베이스 관리자 계정으로 접근하도록 제한 | auto | - | - | - |
| D-18 | Oracle | 응용프로그램 또는 DBA 계정의 Role이 Public으로 설정되지 않도록 조정 | confirm | - | - | - |
| D-19 | Oracle | OS_ROLES, REMOTE_OS_AUTHENTICATION, REMOTE_OS_ROLES를 FALSE로 설정 | confirm | 일부 — SPFILE 값은 원래대로 되돌리지만 반영하려면 인스턴스 재기동이 필요함 | 인스턴스 재기동 — 재기동 동안 DB 접속 끊김 | 필요 |
| D-21 | Oracle | 인가되지 않은 GRANT OPTION 사용 제한 | confirm | - | - | - |
| D-22 | Oracle | 데이터베이스의 자원 제한 기능을 TRUE로 설정 | confirm | - | - | - |
| D-26 | Oracle | 데이터베이스의 접근, 변경, 삭제 등의 감사 기록이 기관의 감사 기록 정책에 적합하도록 설정 | confirm | 일부 — SPFILE 값은 원래대로 되돌리지만 반영하려면 인스턴스 재기동이 필요함 | 인스턴스 재기동 — 재기동 동안 DB 접속 끊김 | 필요 |
| D-03 | MSSQL | 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 | confirm | - | - | - |
| D-10 | MSSQL | 원격에서 DB 서버로의 접속 제한 | confirm | - | - | - |
| D-11 | MSSQL | DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 | confirm | - | - | - |
| D-16 | MSSQL | Windows 인증 모드 사용 | auto | - | - | - |
| D-23 | MSSQL | xp_cmdshell 사용 제한 | confirm | - | - | - |
| D-24 | MSSQL | Registry Procedure 권한 제한 | auto | - | - | - |
| D-26 | MSSQL | 데이터베이스의 접근, 변경, 삭제 등의 감사 기록이 기관의 감사 기록 정책에 적합하도록 설정 | confirm | - | - | - |
