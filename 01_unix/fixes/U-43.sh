# U-43 (상) NIS, NIS+ 점검 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    fix_service_disable ypserv ypbind ypxfrd yppasswdd
    pkill -f 'ypserv|ypbind|ypxfrd|rpc\.yppasswdd|rpc\.ypupdated' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="NIS 관련 서비스(ypserv/ypbind 등)를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable ypserv ypbind"
}
