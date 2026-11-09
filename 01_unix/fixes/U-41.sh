# U-41 (상) 불필요한 automountd 제거 — 조치
# 변경: autofs 서비스 정지·비활성화, automount/autofs 프로세스 종료
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
# 영향: 실행 중인 autofs 중지·automount 종료 — 자동 마운트된 원격 파일시스템 접근 끊김
run_fix() {
    fix_service_disable autofs
    fix_kill_procs 'automount|autofs'
    FIX_STATUS="APPLIED"
    FIX_DETAIL="automount(autofs) 서비스를 정지/비활성화함(CD-ROM 등 자동 마운트가 더 이상 동작하지 않음)"
    FIX_EVIDENCE="systemctl disable autofs"
}
