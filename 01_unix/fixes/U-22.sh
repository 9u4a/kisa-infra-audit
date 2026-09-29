# U-22 (상) /etc/services 파일 소유자 및 권한 설정 — 조치
run_fix() { fix_set_owner_perm "/etc/services" "root" 644; }
