# U-21 (상) /etc/(r)syslog.conf 파일 소유자 및 권한 설정 — 조치
run_fix() {
    if [ -f /etc/rsyslog.conf ]; then
        fix_set_owner_perm "/etc/rsyslog.conf" "root" 640
    elif [ -f /etc/syslog.conf ]; then
        fix_set_owner_perm "/etc/syslog.conf" "root" 640
    else
        FIX_STATUS="NA"; FIX_DETAIL="rsyslog.conf/syslog.conf 모두 존재하지 않아 조치 대상 없음"; FIX_EVIDENCE=""
    fi
}
