# U-16 (상) /etc/passwd 파일 소유자 및 권한 설정 — 조치
run_fix() { fix_set_owner_perm "/etc/passwd" "root" 644; }
