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

    echo "ENCRYPT_METHOD DES" >> /etc/login.defs                        # U-13
    # 주의: 기본 debian:12 의 /etc/login.defs 에 이미 활성 "UMASK 022" 줄이 있고, U-30 check는
    # /etc/profile -> /etc/login.defs 순으로 읽어 "나중에 읽은 값"을 최종값으로 쓴다 - /etc/profile
    # 에만 덧붙이면 login.defs 값이 덮어써 VULN이 재현되지 않는 실수가 있었다(실기 테스트로 발견).
    sed -i 's/^UMASK.*/UMASK\t\t000/' /etc/login.defs                   # U-30

    chmod 666 /etc/passwd                                               # U-16
    chmod 644 /etc/shadow                                                # U-18
    chmod 666 /etc/hosts                                                 # U-19

    # U-52: 실제 telnetd 데몬을 띄우려면 xinetd/inetd 가 슈퍼바이저로 돌고 있어야 하는데
    # `docker run`만으로는 init 시스템이 없어 불안정하다 - check가 보는 xinetd.d 설정 파일
    # 자체만 만들어 같은 판정 경로(checks/U-52.sh 의 xinetd.d/telnet "disable = no" 분기)를
    # 거친다. 패키지 설치 없이도 충분하다(check는 패키지 존재가 아니라 이 파일을 본다).
    mkdir -p /etc/xinetd.d
    printf 'service telnet\n{\n\tdisable = no\n\tflags = REUSE\n\tsocket_type = stream\n}\n' > /etc/xinetd.d/telnet

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
else
    echo "usage: setup.sh <vuln|hardened>" >&2
    exit 2
fi
