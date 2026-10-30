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
c_U_37__crontab_750() { chmod 750 /usr/bin/crontab; }
c_U_37__crontab_suid() { chmod 4755 /usr/bin/crontab; }
c_U_37__cron_allow_644() { chmod 750 /usr/bin/crontab; echo root > /etc/cron.allow; chmod 644 /etc/cron.allow; }
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
c_U_55__ftp_shell() { echo "ftp:x:2100:2100::/srv/ftp:/bin/sh" >> /etc/passwd; echo "ftp:x:2100:" >> /etc/group; }
c_U_55__ftp_nologin() { echo "ftp:x:2100:2100::/srv/ftp:/usr/sbin/nologin" >> /etc/passwd; echo "ftp:x:2100:" >> /etc/group; }
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
    find /var/log -type f ! -user root -exec chown root {} +
    find /var/log -type f -perm /7133 -exec chmod u-xs,g-wxs,o-wx,-t {} +
}
