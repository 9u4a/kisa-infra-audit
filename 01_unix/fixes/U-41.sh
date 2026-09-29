# U-41 (상) 불필요한 automountd 제거 — 조치
run_fix() {
    fix_service_disable autofs
    pkill -f 'automountd|autofs' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="automount(autofs) 서비스를 정지/비활성화함(CD-ROM 등 자동 마운트가 더 이상 동작하지 않음)"
    FIX_EVIDENCE="systemctl disable autofs"
}
