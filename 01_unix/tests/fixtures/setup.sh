#!/bin/sh
# 01_unix/tests/fixtures/setup.sh <vuln|hardened> — Dockerfile이 빌드 중 호출해 컨테이너를
# 의도적으로 취약/강화된 상태로 만든다. 모든 항목을 다 다루지는 않는다(초기 범위: 계정·파일
# 권한 위주 ~20항목 + 서비스 2종) - 01_unix/CLAUDE.md "테스트 커버리지" 절 참고, 이후 세션에서
# 계속 넓혀갈 것.
set -eu
MODE=$1

if [ "$MODE" = "vuln" ]; then
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config                  # U-01

    echo "testvuln:plainhash123:2000:2000::/home/testvuln:/bin/sh" >> /etc/passwd   # U-04
    echo "orphanuser:x:2001:9999::/home/orphanuser:/bin/sh" >> /etc/passwd          # U-09 (gid 9999 미존재)
    echo "dupuser:x:0:0::/home/dupuser:/bin/sh" >> /etc/passwd                      # U-10 (uid 0 중복)
    sed -i 's#^daemon:\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):.*#daemon:\1:\2:\3:\4:\5:/bin/bash#' /etc/passwd   # U-11

    # U-13 (진단 검수 U-R13): login.defs 는 SHA512(양호)지만 /etc/shadow 에 MD5($1$) 해시가 남은 계정 - 예전 check 는
    # login.defs 만 보고 GOOD 이었다.
    sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' /etc/login.defs
    echo "md5user:x:2002:2002::/nonexistent:/usr/sbin/nologin" >> /etc/passwd
    echo 'md5user:$1$kisasalt$Qp0wYQK0rM1y9vUe6m3Vx/:19000:0:99999:7:::' >> /etc/shadow
    # U-30 (진단 검수 U-R15): login.defs 는 027(양호)이지만 로그인 뒤 셸이 읽는 /etc/profile.d 에서 002 로 덮어씀.
    # 예전 check 는 /etc/profile → login.defs 순으로 읽어 login.defs 값(027)을 최종값으로 봐 GOOD 이었다.
    sed -i 's/^UMASK.*/UMASK\t\t027/' /etc/login.defs
    echo "umask 002" > /etc/profile.d/kisa-umask.sh

    chmod 666 /etc/passwd                                               # U-16
    chmod 644 /etc/shadow                                                # U-18
    chmod 666 /etc/hosts                                                 # U-19

    # U-52: 실제 telnetd 데몬을 띄우려면 xinetd/inetd 가 슈퍼바이저로 돌고 있어야 하는데
    # `docker run`만으로는 init 시스템이 없어 불안정하다 - check가 보는 xinetd.d 설정 파일
    # 자체만 만들어 같은 판정 경로(checks/U-52.sh 의 xinetd.d/telnet "disable = no" 분기)를
    # 거친다. 패키지 설치 없이도 충분하다(check는 패키지 존재가 아니라 이 파일을 본다).
    mkdir -p /etc/xinetd.d
    printf 'service telnet\n{\n\tdisable = no\n\tflags = REUSE\n\tsocket_type = stream\n}\n' > /etc/xinetd.d/telnet

    # ---- 진단 검수(1.3.1) U-R2~U-R17 재현 픽스처: 예전 check 가 GOOD 으로 잘못 판정하던 상태 ----
    # U-17 (U-R2): 그룹 쓰기만 있는 유닛 파일(0664) - 예전 -perm -0022 는 그룹·기타 "모두" 쓰기일 때만 잡았다.
    mkdir -p /etc/systemd/system
    printf '[Service]\nExecStart=/bin/true\n' > /etc/systemd/system/kisa-r2.service
    chmod 664 /etc/systemd/system/kisa-r2.service
    # U-28 (U-R3): 규칙셋은 있으나 정책 accept·ACCEPT all 뿐인 방화벽(가짜 nft/iptables - 컨테이너에 커널 방화벽
    # 권한이 없어 출력만 흉내 낸다). 예전 check 는 "규칙셋 비어 있지 않음"/"INPUT 규칙 1개 이상"이면 GOOD 이었다.
    mkdir -p /usr/local/sbin
    printf '#!/bin/sh\n[ "$1 $2" = "list ruleset" ] || exit 1\nprintf "table inet filter {\\n\\tchain input {\\n\\t\\ttype filter hook input priority filter; policy accept;\\n\\t\\tct state established accept\\n\\t}\\n}\\n"\n' > /usr/local/sbin/nft
    printf '#!/bin/sh\ncase "$*" in -V) echo "iptables v1.8.9 (nf_tables)" ;; *-S\\ INPUT*) printf -- "-P INPUT ACCEPT\\n-A INPUT -j ACCEPT\\n" ;; *) exit 1 ;; esac\n' > /usr/local/sbin/iptables
    chmod 755 /usr/local/sbin/nft /usr/local/sbin/iptables
    # U-03 (U-R4): 주석 처리된 pam_tally2 deny 줄 + PAM 스택에 모듈 없이 faillock.conf 만 있음
    echo "#auth required pam_tally2.so deny=5 onerr=fail" >> /etc/pam.d/common-auth
    mkdir -p /etc/security && echo "deny = 5" >> /etc/security/faillock.conf
    # U-50/U-51 (U-R5): Debian 배치 - named.conf 는 include + 주석뿐, 실제 설정은 include 파일의 여러 줄 블록.
    # 예전 check 는 include 를 따라가지 않고 주석 줄의 값을 읽어 GOOD 이었다.
    mkdir -p /etc/bind
    printf '// allow-transfer { 10.0.0.1; };\n// allow-update { none; };\ninclude "/etc/bind/named.conf.options";\n' > /etc/bind/named.conf
    printf 'options {\n\tdirectory "/var/cache/bind";\n\tallow-transfer {\n\t\tany;\n\t};\n};\nzone "example.com" {\n\ttype master;\n\tfile "/etc/bind/db.example";\n\tallow-update {\n\t\tany;\n\t};\n};\n' > /etc/bind/named.conf.options
    # U-34/U-36 (U-R6): inetd 로 기동되는 finger·rsh - 연결 전에는 프로세스가 없어 예전 check 는 GOOD 이었다.
    # U-27 (U-R14): r-command(inetd shell) 사용 중 + hosts.equiv 의 "host +"(그 호스트의 모든 사용자 신뢰) 형태.
    printf 'finger\tstream\ttcp\tnowait\tnobody\t/usr/sbin/tcpd\t/usr/sbin/in.fingerd\nshell\tstream\ttcp\tnowait\troot\t/usr/sbin/tcpd\t/usr/sbin/in.rshd\n' > /etc/inetd.conf
    echo "trusted.example.com +" > /etc/hosts.equiv
    chmod 600 /etc/hosts.equiv
    # U-12 (U-R7): TMOUT=0 은 자동 종료 해제 - 예전 check 는 0 ≤ 600 으로 GOOD 이었다.
    echo "export TMOUT=0" > /etc/profile.d/kisa-tmout.sh
    # U-06 (U-R8): sufficient pam_wheel.so trust 만 있음(wheel 구성원 무암호 통과, 나머지 제한 없음)
    echo "auth sufficient pam_wheel.so trust use_uid" >> /etc/pam.d/su
    # U-14 (U-R9): 따옴표로 감싼 PATH 맨 앞의 "."
    echo 'export PATH=".:$PATH"' >> /root/.bashrc
    # U-67 (U-R11): 하위 디렉터리의 world-writable 로그(예전 check 는 최상위 30개만 봤다)
    mkdir -p /var/log/kisa && : > /var/log/kisa/app.log && chmod 666 /var/log/kisa/app.log
    # U-02 (U-R12): PASS_MAX_DAYS 90 이지만 복잡성(minlen) 설정 없음 - 예전 check 는 pwquality.conf 가 없으면
    # 주기 하나만으로 GOOD 이었다(이제 일부만 설정 = MANUAL).
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    # U-35 (U-R15): 앞 공유는 guest ok = yes, 마지막 공유는 no - 예전 check 는 마지막 값만 봤다.
    mkdir -p /etc/samba
    printf '[global]\n\tworkgroup = KISA\n[pub]\n\tpath = /srv/pub\n\tguest ok = yes\n[priv]\n\tpath = /srv/priv\n\tguest ok = no\n' > /etc/samba/smb.conf
    # U-40 (U-R15): 호스트를 생략한 export("/srv (rw)") = 모든 호스트에 공개
    echo "/srv (rw,sync)" > /etc/exports
    # U-56/U-57 (U-R15): ftpusers 는 계정 제한일 뿐 IP 접근 제어가 아니고, userlist_deny=NO 의 user_list 는 허용
    # 목록이라 root 가 들어 있으면 root 접속 허용 - 예전 check 는 둘 다 GOOD 이었다.
    echo "daemon" > /etc/ftpusers
    printf 'anonymous_enable=NO\nuserlist_enable=YES\nuserlist_deny=NO\n' > /etc/vsftpd.conf
    echo "root" > /etc/vsftpd.user_list
    # U-59~U-61 (U-R15): 주 파일은 v3(createUser)뿐이고 includeDir 아래에 IPv6 v2c 기본 community 전체 허용
    mkdir -p /etc/snmp/snmpd.conf.d
    printf 'createUser kisav3 SHA "KisaAuthPass#2026" AES\nincludeDir /etc/snmp/snmpd.conf.d\n' > /etc/snmp/snmpd.conf
    echo "rocommunity6 public default" > /etc/snmp/snmpd.conf.d/v2.conf

elif [ "$MODE" = "hardened" ]; then
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config                   # U-01

    if grep -q '^PASS_MAX_DAYS' /etc/login.defs; then
        sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    else
        echo "PASS_MAX_DAYS   90" >> /etc/login.defs
    fi
    mkdir -p /etc/security
    echo "minlen = 8" >> /etc/security/pwquality.conf                   # U-02

    echo "deny = 5" >> /etc/security/faillock.conf                      # U-03

    echo "ENCRYPT_METHOD SHA512" >> /etc/login.defs                     # U-13
    echo "umask 027" >> /etc/profile                                    # U-30

    mkdir -p /etc/pam.d
    [ -f /etc/pam.d/su ] || : > /etc/pam.d/su
    echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su          # U-06

    # ---- 진단 검수(1.3.1) 재현 픽스처의 양호 쪽 ----
    # U-03 (U-R4): faillock.conf 는 PAM 스택에 pam_faillock.so 가 있을 때만 쓰인다
    echo "auth required pam_faillock.so preauth" >> /etc/pam.d/common-auth
    # U-28 (U-R3): input 훅 체인의 기본 정책이 drop 인 nft 규칙셋(가짜 nft - vuln 쪽 설명 참고)
    mkdir -p /usr/local/sbin
    printf '#!/bin/sh\n[ "$1 $2" = "list ruleset" ] || exit 1\nprintf "table inet filter {\\n\\tchain input {\\n\\t\\ttype filter hook input priority filter; policy drop;\\n\\t\\ttcp dport 22 ip saddr 10.0.0.0/8 accept\\n\\t}\\n}\\n"\n' > /usr/local/sbin/nft
    chmod 755 /usr/local/sbin/nft
    # U-12 (U-R7): 따옴표·"export TMOUT=" 형태 - 예전 check 는 인식하지 못해 VULN 이었다.
    echo 'export TMOUT="600"' > /etc/profile.d/kisa-tmout.sh
    # U-11 (U-R17): /usr/bin/false 도 로그인 불가 쉘 - 예전 check 는 /bin/false 만 인정해 VULN 이었다.
    sed -i 's#^sys:\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):.*#sys:\1:\2:\3:\4:\5:/usr/bin/false#' /etc/passwd
    # U-50/U-51 (U-R5): include 된 파일에서 전송 대상 제한·동적 업데이트 비활성
    mkdir -p /etc/bind
    printf '// allow-transfer { any; };\ninclude "/etc/bind/named.conf.options";\n' > /etc/bind/named.conf
    printf 'options {\n\tallow-transfer {\n\t\t10.0.0.2;\n\t};\n\tallow-update { none; };\n};\nzone "example.com" {\n\ttype master;\n\tfile "/etc/bind/db.example";\n};\n' > /etc/bind/named.conf.options
    # U-34 (U-R6): inetd.conf 의 주석 처리된 항목은 활성이 아니다
    printf '#finger\tstream\ttcp\tnowait\tnobody\t/usr/sbin/tcpd\t/usr/sbin/in.fingerd\n' > /etc/inetd.conf
else
    echo "usage: setup.sh <vuln|hardened>" >&2
    exit 2
fi
