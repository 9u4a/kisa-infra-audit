# U-34 (상) Finger 서비스 비활성화 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    fix_service_disable finger.socket
    fix_xinetd_disable /etc/xinetd.d/finger
    # check 가 /etc/inetd.conf 를 보게 되어(진단 검수 U-R6) 조치도 같은 항목을 주석 처리한다.
    fix_inetd_disable finger
    pkill -f 'fingerd|in.fingerd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Finger 서비스를 정지/비활성화함(systemd 유닛 및 xinetd 설정)"
    FIX_EVIDENCE="finger.socket disable, xinetd disable=yes"
}
