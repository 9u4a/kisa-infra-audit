#!/bin/sh
# 01_unix/tests/fixtures/cases/cases.sh — 항목별 양방향 케이스의 상태 준비(1.4.0). case_run.sh 가 source 한다.
# 함수 이름 = c_<코드>__<이름>(- 는 _ 로). cases.json 의 각 항목과 이름으로 짝지으며, 함수가 없으면 러너가 FAIL.
# 기대 판정(cases.json expect)은 guide.json 판단기준에서 정한 것이다(도구 출력을 그대로 고정한 것이 아님).
# 실행 환경: Dockerfile.cases(systemd PID 1) 컨테이너, base 픽스처(setup.sh hardened 등) 적용 뒤.
# 서비스 항목은 같은 이름의 가짜 유닛(ExecStart=sleep)으로 만든다 - check 는 유닛 상태(is-active/is-enabled)·프로세스만 보고,
# 조치는 systemctl stop/disable 로 같은 경로를 탄다.

# fake_unit <유닛 이름> <installed|enabled|active> [ExecStart 실행 파일] — /etc/systemd/system/<이름>.service
fake_unit() {
    _exe=${3:-/bin/sleep}
    printf '[Unit]\nDescription=KISA test fake %s\n[Service]\nExecStart=%s infinity\n[Install]\nWantedBy=multi-user.target\n' \
        "$1" "$_exe" > "/etc/systemd/system/$1.service"
    systemctl daemon-reload
    case "$2" in
        enabled) systemctl enable "$1.service" >/dev/null 2>&1 ;;
        active) systemctl start "$1.service" ;;
    esac
}

# ---- 1. 계정 관리 ----
c_U_02__weak_policy() {
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   180/' /etc/login.defs
    echo "minlen = 6" > /etc/security/pwquality.conf
}

# rhel(Rocky 9, Dockerfile.cases.rhel) 전용 - authselect 가 관리하는 PAM(system-auth 는 /etc/authselect 로의 심볼릭 링크)
c_U_03__authselect_faillock_default() { authselect enable-feature with-faillock >/dev/null; }
c_U_03__authselect_faillock_deny5() {
    authselect enable-feature with-faillock >/dev/null
    sed -i 's/^#[[:space:]]*deny[[:space:]]*=.*/deny = 5/' /etc/security/faillock.conf
}
c_U_03__authselect_no_faillock() { printf 'deny = 5\n' >> /etc/security/faillock.conf; }
# authselect 가 관리하지 않는 PAM(G-07 Rocky 9 kickstart 최소 설치 실측: authselect current "기존 구성이 없습니다", system-auth 는 일반 파일).
# Rocky 9 authselect 1.2 에는 opt-out 이 없어 링크를 실제 파일로 바꾸고 authselect.conf 를 지워 같은 상태를 만든다
c_U_03__authselect_unmanaged() {
    for f in system-auth password-auth; do cp --remove-destination "$(readlink -f /etc/pam.d/$f)" "/etc/pam.d/$f"; done
    rm -f /etc/authselect/authselect.conf
    printf 'deny = 5\n' >> /etc/security/faillock.conf
}
c_U_06__su_wheel_required() { sed -i 's/^#\(auth[[:space:]]*required[[:space:]]*pam_wheel\.so use_uid\)$/\1/' /etc/pam.d/su; }
c_U_06__su_wheel_trust_only() {
    sed -i 's/^#\(auth[[:space:]]*sufficient[[:space:]]*pam_wheel\.so trust use_uid\)$/\1/' /etc/pam.d/su
    useradd -m -G wheel kisaadm
}

# ---- 2. 파일 및 디렉토리 관리 ----
c_U_18__shadow_400() { chown root /etc/shadow && chmod 400 /etc/shadow; }
c_U_20__inetd_600() { chmod 600 /etc/inetd.conf; }
c_U_21__rsyslog_640() { printf 'auth,authpriv.*\t/var/log/auth.log\n' > /etc/rsyslog.conf; chmod 640 /etc/rsyslog.conf; }
c_U_21__rsyslog_644() { printf 'auth,authpriv.*\t/var/log/auth.log\n' > /etc/rsyslog.conf; chmod 644 /etc/rsyslog.conf; }
c_U_22__services_644() { printf 'ssh\t\t22/tcp\n' > /etc/services; chmod 644 /etc/services; }
c_U_22__services_666() { printf 'ssh\t\t22/tcp\n' > /etc/services; chmod 666 /etc/services; }
c_U_24__bashrc_other_write() { chmod o+w /root/.bashrc; }
c_U_26__dev_regular_file() { printf 'fake\n' > /dev/kisa-fake-dev; }
c_U_29__hosts_lpd_644() { echo "printhost" > /etc/hosts.lpd; chmod 644 /etc/hosts.lpd; }
c_U_29__hosts_lpd_600() { echo "printhost" > /etc/hosts.lpd; chmod 600 /etc/hosts.lpd; }
c_U_31__home_other_write() { chmod 777 /root; }
c_U_31__home_wrong_owner() {
    # 로그인 계정 kisau 의 홈이 root 소유(계정 소유 아님)
    echo "kisau:x:2300:2300::/home/kisau:/bin/sh" >> /etc/passwd
    echo "kisau:x:2300:" >> /etc/group
    mkdir -p /home/kisau && chmod 755 /home/kisau
}
c_U_32__homes_exist() {
    # 홈이 없는 계정(Debian 기본 시스템 계정 list → /var/list, irc → /run/ircd 등)의 홈을 만든다
    awk -F: '$6 != "" && $6 != "/" && $6 != "/nonexistent" && $6 != "/nonexisting" { print $6 }' /etc/passwd | while IFS= read -r h; do
        [ -d "$h" ] || mkdir -p "$h"
    done
}
c_U_35__vsftpd_anon_no() { printf 'listen=YES\nanonymous_enable=NO\n' > /etc/vsftpd.conf; }
c_U_35__vsftpd_anon_yes() { printf 'listen=YES\nanonymous_enable=YES\n' > /etc/vsftpd.conf; }

# ---- 3. 서비스 관리 ----
# Rocky 9(cronie)는 기본 상태가 crontab SUID(4755) + /etc/cron.deny 644 라 기준 초과 - 양호 쪽은 cron.deny 도 640 으로,
# SUID 쪽은 cron.deny 만 640 으로 바꿔(SUID 는 그대로) 판정 원인을 crontab 하나로 좁힌다(Debian 은 cron.deny 없음)
# 1.5.0 A1: /etc/crontab·/etc/cron.d/* 도 판정 대상(기준 640) - 배포판 기본값(644)을 640 으로 맞춘 상태를 양호 기준선으로 쓴다
u37_base() {
    chmod 750 /usr/bin/crontab
    [ ! -f /etc/cron.deny ] || chmod 640 /etc/cron.deny
    [ ! -f /etc/crontab ] || chmod 640 /etc/crontab
    [ ! -d /etc/cron.d ] || find /etc/cron.d -maxdepth 1 -type f -exec chmod 640 {} +
}
c_U_37__crontab_750() { u37_base; }
c_U_37__crontab_suid() { u37_base; chmod 4755 /usr/bin/crontab; }
c_U_37__cron_allow_644() { u37_base; echo root > /etc/cron.allow; chmod 644 /etc/cron.allow; }
c_U_38__inetd_echo_commented() { printf '#echo\tstream\ttcp\tnowait\troot\tinternal\n' >> /etc/inetd.conf; }
c_U_38__inetd_echo() { printf 'echo\tstream\ttcp\tnowait\troot\tinternal\n' >> /etc/inetd.conf; }
c_U_39__nfs_server_enabled() { fake_unit nfs-server enabled; }
c_U_39__nfs_server_disabled() { fake_unit nfs-server installed; }
c_U_40__exports_restricted() { echo "/srv 10.0.0.0/24(ro,root_squash)" > /etc/exports; chmod 644 /etc/exports; }
c_U_41__autofs_active() { fake_unit autofs active; }
c_U_42__rstatd_running() {
    # 가이드 나열 RPC 데몬(rstatd)과 같은 이름의 프로세스(sleep 사본)를 systemd 유닛으로 띄운다
    cp /bin/sleep /usr/local/sbin/rpc.rstatd
    fake_unit rstatd active /usr/local/sbin/rpc.rstatd
}
c_U_43__ypbind_active() { fake_unit ypbind active; }
c_U_44__inetd_tftp() { printf 'tftp\tdgram\tudp\twait\tnobody\t/usr/sbin/tcpd\t/usr/sbin/in.tftpd\n' >> /etc/inetd.conf; }
c_U_44__xinetd_talk() {
    mkdir -p /etc/xinetd.d
    printf 'service talk\n{\n\tdisable = no\n\tsocket_type = dgram\n}\n' > /etc/xinetd.d/talk
}
c_U_45__postfix_installed() {
    printf '#!/bin/sh\n[ "$1" = "mail_version" ] && echo "mail_version = 3.7.11"\n' > /usr/local/sbin/postconf
    chmod 755 /usr/local/sbin/postconf
}
c_U_46__sendmail_no_restrictqrun() { mkdir -p /etc/mail; printf 'O PrivacyOptions=authwarnings,noexpn,novrfy\n' > /etc/mail/sendmail.cf; }
c_U_46__sendmail_restrictqrun() { mkdir -p /etc/mail; printf 'O PrivacyOptions=authwarnings,goaway,restrictqrun\n' > /etc/mail/sendmail.cf; }
c_U_47__sendmail_promiscuous_relay() { mkdir -p /etc/mail; printf "FEATURE(\`promiscuous_relay')dnl\nMAILER(smtp)dnl\n" > /etc/mail/sendmail.mc; }
c_U_47__sendmail_relay_restricted() { mkdir -p /etc/mail; printf "FEATURE(\`access_db')dnl\nMAILER(smtp)dnl\n" > /etc/mail/sendmail.mc; }
c_U_47__sendmail_promiscuous_commented() {
    mkdir -p /etc/mail
    printf "dnl FEATURE(\`promiscuous_relay')dnl
#FEATURE(\`promiscuous_relay')dnl
MAILER(smtp)dnl
" > /etc/mail/sendmail.mc
}
c_U_48__sendmail_no_noexpn() { mkdir -p /etc/mail; printf 'O PrivacyOptions=authwarnings,restrictqrun\n' > /etc/mail/sendmail.cf; }
c_U_48__sendmail_goaway() { mkdir -p /etc/mail; printf 'O PrivacyOptions=goaway,restrictqrun\n' > /etc/mail/sendmail.cf; }
c_U_49__bind_installed() {
    printf '#!/bin/sh\n[ "$1" = "-v" ] && echo "BIND 9.18.33-1~deb12u2-Debian (Extended Support Version) <id:>"\n' > /usr/local/sbin/named
    chmod 755 /usr/local/sbin/named
}
c_U_54__vsftpd_active() { fake_unit vsftpd active; }
c_U_54__vsftpd_disabled() { fake_unit vsftpd installed; }
# ftp 계정: Debian 은 기본으로 없어 만들고, Rocky 9 는 기본 계정(uid 14, /sbin/nologin)의 쉘만 바꾼다
ftp_account() {
    if grep -q '^ftp:' /etc/passwd; then usermod -s "$1" ftp
    else echo "ftp:x:2100:2100::/srv/ftp:$1" >> /etc/passwd; echo "ftp:x:2100:" >> /etc/group; fi
}
c_U_55__ftp_shell() { ftp_account /bin/sh; }
c_U_55__ftp_nologin() { ftp_account /usr/sbin/nologin; }
c_U_56__proftpd_no_limit() { mkdir -p /etc/proftpd; printf 'ServerName "ftp"\nPort 21\n' > /etc/proftpd/proftpd.conf; }
c_U_56__proftpd_limit_login() {
    mkdir -p /etc/proftpd
    printf 'ServerName "ftp"\n<Limit LOGIN>\n  Allow from 10.0.0.0/8\n  DenyAll\n</Limit>\n' > /etc/proftpd/proftpd.conf
}
c_U_58__snmpd_enabled() { fake_unit snmpd enabled; }
c_U_58__snmpd_disabled() { fake_unit snmpd installed; }
c_U_58__snmpd_conf_viewer() {
    # 데몬은 없고 설정 파일을 보는 프로세스만 있음 - 실행 파일 이름은 tail
    mkdir -p /etc/snmp && echo "rocommunity kisaview 127.0.0.1" > /etc/snmp/snmpd.conf
    printf '[Service]
ExecStart=/usr/bin/tail -f /etc/snmp/snmpd.conf
' > /etc/systemd/system/kisa-viewer.service
    systemctl daemon-reload && systemctl start kisa-viewer.service
}
c_U_62__banners_set() {
    echo "Authorized access only. All activity may be monitored." > /etc/motd
    echo "Authorized access only." > /etc/issue
    echo "Authorized access only." > /etc/issue.net
    echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
}
c_U_63__sudoers_440() { printf 'root ALL=(ALL:ALL) ALL\n' > /etc/sudoers; chmod 440 /etc/sudoers; }
c_U_63__sudoers_666() { printf 'root ALL=(ALL:ALL) ALL\n' > /etc/sudoers; chmod 666 /etc/sudoers; }

# ---- 5. 로그 관리 ----
c_U_65__chrony_active() {
    mkdir -p /etc/chrony && echo "server 10.0.0.1 iburst" > /etc/chrony/chrony.conf
    fake_unit chrony active
}
c_U_65__chrony_stopped() {
    mkdir -p /etc/chrony && echo "server 10.0.0.1 iburst" > /etc/chrony/chrony.conf
    fake_unit chrony installed
}
c_U_66__rsyslog_active_auth() {
    printf 'auth,authpriv.*\t/var/log/auth.log\n*.*;auth,authpriv.none\t-/var/log/syslog\n' > /etc/rsyslog.conf
    fake_unit rsyslog active
}
c_U_66__rsyslog_stopped() {
    printf 'auth,authpriv.*\t/var/log/auth.log\n' > /etc/rsyslog.conf
    fake_unit rsyslog installed
}
c_U_67__logs_root_644() {
    # Rocky 9 는 기본 상태가 이미 기준 이내라(바뀌는 파일이 wtmp 뿐 - 스냅숏 제외) 기준 초과 로그를 하나 만든 뒤 함께 정리한다
    : > /var/log/kisa-app.log && chmod 666 /var/log/kisa-app.log
    find /var/log -type f ! -user root -exec chown root {} +
    find /var/log -type f -perm /7133 -exec chmod u-xs,g-wxs,o-wx,-t {} +
}

# ---- 실무 적용 검증(KNOWN_ISSUES §4, 1.5.0) -------------------------------------------------------------------------
# P-14: 강화 기준의 PermitRootLogin no 를 prohibit-password(OpenSSH 기본값)로 바꾼다 - 키 인증 root 직접 접속 허용 = 취약
c_U_01__sshd_prohibit_password() {
    sed -i 's/^PermitRootLogin no$/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    # Rocky 컨테이너는 sshd 를 한 번도 띄우지 않아 호스트 키가 없다 - 조치의 sshd -t 사전 검사가 통과하도록 만든다
    ssh-keygen -A >/dev/null 2>&1
    # 조치의 안전장치(root 외 관리자 계정이 있어야 root 원격 접속을 막음)를 통과시킬 관리자 계정(Debian sudo / Rocky wheel)
    if getent group sudo >/dev/null 2>&1; then useradd -m -G sudo kisaadm; else useradd -m -G wheel kisaadm; fi
}
# P-02: /etc/passwd 비밀번호 필드가 빈 계정(비밀번호 없이 로그인) - 예전에는 GOOD 이었다
c_U_04__passwd_empty_field() {
    useradd -M -s /bin/sh kisanopw
    sed -i 's/^kisanopw:x:/kisanopw::/' /etc/passwd
}
# P-15: 전체 공개 NFS 공유(조치는 주석 처리 + exportfs -ra)
c_U_40__exports_open() { echo "/srv *(rw,no_root_squash)" > /etc/exports; chmod 644 /etc/exports; }
# P-03: Exim(MTA)만 설치된 서버 - 설정 조회 명령(exim4 -bP)을 흉내 내는 가짜 실행 파일
exim_fake() {
    printf '#!/bin/sh\necho "relay_from_hosts = <; 127.0.0.1 ; ::1"\necho "acl_smtp_rcpt = acl_check_rcpt"\n' > /usr/local/sbin/exim4
    chmod 755 /usr/local/sbin/exim4
}
c_U_47__exim_only() { exim_fake; }
c_U_48__exim_only() { exim_fake; }

# ---- 진단 판정 신뢰성(1.5.0 A·B·C 외부 검수) ------------------------------------------------------------------------
# A1 U-37: 작업 목록(스풀) 0644 - 예전 -perm -0007 은 기타 rwx 가 "모두" 있을 때만 잡아 GOOD 이었다
c_U_37__spool_644() {
    u37_base
    d=/var/spool/cron/crontabs; [ -d "$d" ] || d=/var/spool/cron
    printf '0 0 * * * true\n' > "$d/root"; chmod 644 "$d/root"
}
# A1 U-37: /etc/crontab 644(배포판 기본값) - 예전에는 /etc/crontab·cron.d 를 보지 않아 GOOD
c_U_37__etc_crontab_644() { u37_base; chmod 644 /etc/crontab; }
# C1: 파일 이름에 EUC-KR 바이트("가")가 든 cron.d 파일 - 증적(ls -l)에 섞여 예전에는 result.json 이 잘못된 UTF-8
c_U_37__cron_d_euckr_name() {
    u37_base
    f=/etc/cron.d/kisa-$(printf '\260\241')
    printf '0 0 * * * root true\n' > "$f"; chmod 644 "$f"
}
# A2 U-28: 정책 accept + "ct state invalid drop" 한 줄(가짜 nft) - 예전 GOOD. 조치는 manual 등급(변경 없음)
c_U_28__nft_invalid_only() {
    cat > /usr/local/sbin/nft <<'NFT'
#!/bin/sh
[ "$1 $2" = "list ruleset" ] || exit 1
printf 'table inet filter {\n\tchain input {\n\t\ttype filter hook input priority filter; policy accept;\n\t\tct state invalid drop\n\t\tct state established,related accept\n\t}\n}\n'
NFT
    chmod 755 /usr/local/sbin/nft
}
# A2 U-28: nft 은 정책 accept 뿐, iptables INPUT 은 정책 ACCEPT + INVALID DROP 한 줄(가짜 iptables-nft) - 예전 GOOD
c_U_28__iptables_invalid_only() {
    cat > /usr/local/sbin/nft <<'NFT'
#!/bin/sh
[ "$1 $2" = "list ruleset" ] || exit 1
printf 'table inet filter {\n\tchain input {\n\t\ttype filter hook input priority filter; policy accept;\n\t}\n}\n'
NFT
    cat > /usr/local/sbin/iptables <<'IPT'
#!/bin/sh
case "$*" in
    -V) echo "iptables v1.8.9 (nf_tables)" ;;
    *-S\ INPUT*) printf -- '-P INPUT ACCEPT\n-A INPUT -m conntrack --ctstate INVALID -j DROP\n' ;;
    *) exit 1 ;;
esac
IPT
    chmod 755 /usr/local/sbin/nft /usr/local/sbin/iptables
}
# A2 U-28: 정책 accept 라도 출발지·포트 기준 drop 규칙이 있으면 접근 제한(양호 쪽 회귀)
c_U_28__nft_source_port_drop() {
    cat > /usr/local/sbin/nft <<'NFT'
#!/bin/sh
[ "$1 $2" = "list ruleset" ] || exit 1
printf 'table inet filter {\n\tchain input {\n\t\ttype filter hook input priority filter; policy accept;\n\t\tct state invalid drop\n\t\ttcp dport 22 ip saddr != 10.0.0.0/8 drop\n\t}\n}\n'
NFT
    chmod 755 /usr/local/sbin/nft
}
# A3 U-24: 그룹 쓰기(0664) - 예전 -perm -0002 는 기타 쓰기만 봐서 GOOD
c_U_24__bashrc_group_write() { chmod 664 /root/.bashrc; }
# A4 U-17: /etc/init.d 의 rc 스크립트에 기타 쓰기 - 예전에는 /etc/systemd/system 이 있으면 init.d 를 보지 않아 GOOD
c_U_17__initd_other_write() {
    [ -d /etc/init.d ] || mkdir -p /etc/init.d
    printf '#!/bin/sh\nexit 0\n' > /etc/init.d/kisa-test
    chmod 757 /etc/init.d/kisa-test
}
c_U_17__initd_755() {
    [ -d /etc/init.d ] || mkdir -p /etc/init.d
    printf '#!/bin/sh\nexit 0\n' > /etc/init.d/kisa-test
    chmod 755 /etc/init.d/kisa-test
}
# A5 U-27: rsh.socket 이 enabled(재부팅·첫 연결 시 기동, 지금은 inactive) + .rhosts "+ +" - 예전에는 is-active 만 봐서
# "r-command 미사용" GOOD
c_U_27__rsh_socket_enabled() {
    printf '[Unit]\nDescription=KISA test fake rsh\n[Socket]\nListenStream=5514\nAccept=yes\n[Install]\nWantedBy=sockets.target\n' \
        > /etc/systemd/system/rsh.socket
    printf '[Unit]\nDescription=KISA test fake rsh conn\n[Service]\nExecStart=/bin/true\nStandardInput=socket\n' \
        > /etc/systemd/system/rsh@.service
    systemctl daemon-reload
    systemctl enable rsh.socket >/dev/null 2>&1
    printf '+ +\n' > /root/.rhosts; chmod 644 /root/.rhosts
}
# A6 U-62: sshd 배너를 sshd_config.d 드롭인에서만 지정 - 예전에는 주 설정 파일만 봐서 "Banner 미설정" VULN
u62_banners() {
    echo "Authorized access only. All activity may be monitored." > /etc/motd
    echo "Authorized access only." > /etc/issue
    echo "Authorized access only." > /etc/issue.net
}
c_U_62__sshd_dropin_banner() {
    u62_banners
    mkdir -p /etc/ssh/sshd_config.d
    grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config || \
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    echo "Banner /etc/issue.net" > /etc/ssh/sshd_config.d/00-kisa-banner.conf
}
# A6 U-62: 드롭인이 먼저 "Banner none"(sshd 는 처음 값 사용) - 주 설정 파일의 Banner 만 봐서 예전 GOOD. 드롭인 수정은
# 자동 조치하지 않는다 → PARTIAL(변경 없음)
c_U_62__sshd_dropin_banner_none() {
    u62_banners
    mkdir -p /etc/ssh/sshd_config.d
    grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config || \
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    echo "Banner none" > /etc/ssh/sshd_config.d/00-kisa-banner.conf
    echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
}
# A6 U-62: Postfix 기본 smtpd_banner("$myhostname ESMTP $mail_name") - 예전에는 증적에만 남기고 GOOD
postconf_fake() {
    cat > /usr/local/sbin/postconf <<PC
#!/bin/sh
[ "\$1 \$2" = "-h smtpd_banner" ] && echo '$1'
exit 0
PC
    chmod 755 /usr/local/sbin/postconf
}
c_U_62__postfix_default_banner() {
    u62_banners; echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
    postconf_fake '$myhostname ESMTP $mail_name'
}
c_U_62__postfix_custom_banner() {
    u62_banners; echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
    postconf_fake '$myhostname ESMTP Authorized access only'
}
# A6 U-62: BIND 설치(가짜 named) + options 에 version 문 없음(hardened 픽스처의 /etc/bind) - 예전에는 DNS 미검사 GOOD
c_U_62__bind_no_version() {
    u62_banners; echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
    printf '#!/bin/sh\nexit 0\n' > /usr/local/sbin/named; chmod 755 /usr/local/sbin/named
}
# C5 U-55: /usr/bin/false 는 로그인 불가 쉘(U-11 deviation 과 같음) - 예전 VULN
c_U_55__ftp_usr_bin_false() { ftp_account /usr/bin/false; }
# C3 U-55/U-11: shadow 를 쓰지 않는 계정(/etc/passwd 두 번째 필드에 해시) - 예전에는 줄 전체를 증적에 남겼다(S5)
c_U_55__ftp_shell_passwd_hash() {
    ftp_account /bin/sh
    sed -i 's/^ftp:[^:]*:/ftp:KisaPwHash77:/' /etc/passwd
}
c_U_11__daemon_shell_passwd_hash() {
    usermod -s /bin/bash daemon
    sed -i 's/^daemon:[^:]*:/daemon:KisaPwHash77:/' /etc/passwd
}
