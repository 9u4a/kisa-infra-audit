# U-34 (상) Finger 서비스 비활성화 — 조치
# 변경: finger.socket 정지·비활성화, /etc/xinetd.d/finger disable=yes, /etc/inetd.conf finger 줄 주석 처리, fingerd 프로세스 종료
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
# 영향: 실행 중인 finger 서비스 중지(fingerd 종료·xinetd 재적용) — finger 조회 끊김
run_fix() {
    fix_service_disable finger.socket
    fix_xinetd_disable /etc/xinetd.d/finger
    # check 가 /etc/inetd.conf 를 보게 되어(진단 검수 U-R6) 조치도 같은 항목을 주석 처리한다.
    fix_inetd_disable finger
    fix_kill_procs 'fingerd|in.fingerd'
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Finger 서비스를 정지/비활성화함(systemd 유닛 및 xinetd 설정)"
    FIX_EVIDENCE="finger.socket disable, xinetd disable=yes"
}
