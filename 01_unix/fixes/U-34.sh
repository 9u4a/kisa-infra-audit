# U-34 (상) Finger 서비스 비활성화 — 조치
run_fix() {
    fix_service_disable finger.socket
    fix_xinetd_disable /etc/xinetd.d/finger
    pkill -f 'fingerd|in.fingerd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Finger 서비스를 정지/비활성화함(systemd 유닛 및 xinetd 설정)"
    FIX_EVIDENCE="finger.socket disable, xinetd disable=yes"
}
