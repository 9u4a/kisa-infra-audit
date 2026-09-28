# U-21 (상) /etc/(r)syslog.conf 파일 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 소유자 root(또는 bin, sys), 권한 640 이하 / 취약 = 그 외
# 전 Unix 계열 공통 로직: rsyslog.conf 우선, 없으면 syslog.conf.

run_check() {
    if [ -f /etc/rsyslog.conf ]; then
        check_owner_perm "/etc/rsyslog.conf" "root bin sys" 640
    elif [ -f /etc/syslog.conf ]; then
        check_owner_perm "/etc/syslog.conf" "root bin sys" 640
    else
        CHECK_STATUS="NA"
        CHECK_DETAIL="/etc/rsyslog.conf, /etc/syslog.conf 모두 존재하지 않음"
        CHECK_EVIDENCE=""
    fi
}
