# U-29 (하) hosts.lpd 파일 소유자 및 권한 설정 — 조치
run_fix() {
    if [ ! -e /etc/hosts.lpd ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="/etc/hosts.lpd 파일이 없어 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    fix_set_owner_perm "/etc/hosts.lpd" "root" 600
}
