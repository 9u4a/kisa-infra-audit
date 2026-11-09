# U-43 (상) NIS, NIS+ 점검 — 조치
# 변경: ypserv·ypbind·ypxfrd·yppasswdd 서비스 정지·비활성화, NIS 데몬(ypserv/ypbind/ypxfrd/rpc.yppasswdd/rpc.ypupdated) 프로세스 종료
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
# 영향: 실행 중인 NIS(ypserv·ypbind) 중지 — NIS 로 계정·호스트를 조회하던 로그인·이름 해석 실패
run_fix() {
    fix_service_disable ypserv ypbind ypxfrd yppasswdd
    fix_kill_procs 'ypserv|ypbind|ypxfrd|rpc\.yppasswdd|rpc\.ypupdated'
    FIX_STATUS="APPLIED"
    FIX_DETAIL="NIS 관련 서비스(ypserv/ypbind 등)를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable ypserv ypbind"
}
