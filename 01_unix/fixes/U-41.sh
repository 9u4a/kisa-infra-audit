# U-41 (상) 불필요한 automountd 제거 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    fix_service_disable autofs
    pkill -f 'automountd|autofs' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="automount(autofs) 서비스를 정지/비활성화함(CD-ROM 등 자동 마운트가 더 이상 동작하지 않음)"
    FIX_EVIDENCE="systemctl disable autofs"
}
