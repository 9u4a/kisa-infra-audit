# U-22 (상) /etc/services 파일 소유자 및 권한 설정 — 조치
# 변경: /etc/services 소유자 root·권한 644 로 설정
run_fix() { fix_set_owner_perm "/etc/services" "root" 644; }
