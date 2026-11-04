# U-52 (중) Telnet 서비스 비활성화 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    # 텔넷으로 접속한 세션에서 실행하면 아래 프로세스 종료가 자기 세션을 끊는다(실무 적용 검증 P-16, F3) - 조상 프로세스에
    # telnetd 가 있으면 변경하지 않는다.
    _p=$$; _n=0
    while [ "$_p" -gt 1 ] && [ "$_n" -lt 64 ]; do
        case "$(cat "/proc/$_p/comm" 2>/dev/null)" in
            *telnetd*)
                FIX_STATUS="SKIPPED"
                FIX_DETAIL="변경 없음 - 이 조치를 텔넷 세션에서 실행 중임(조상 프로세스 PID $_p). SSH 등 다른 경로로 접속해 다시 실행할 것"
                FIX_EVIDENCE=""
                return ;;
        esac
        _p=$(awk '/^PPid:/ {print $2}' "/proc/$_p/status" 2>/dev/null); _n=$((_n + 1))
        [ -n "$_p" ] || break
    done
    fix_service_disable telnet.socket
    fix_xinetd_disable /etc/xinetd.d/telnet
    # check 가 /etc/inetd.conf 를 보게 되어(진단 검수 U-R6) 조치도 같은 항목을 주석 처리한다.
    fix_inetd_disable telnet
    fix_kill_procs 'in\.telnetd|telnetd'
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Telnet 서비스를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable telnet.socket, xinetd disable=yes"
}
