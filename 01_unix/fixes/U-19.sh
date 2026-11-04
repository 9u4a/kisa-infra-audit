# U-19 (상) /etc/hosts 파일 소유자 및 권한 설정 — 조치
# 변경: /etc/hosts 소유자 root·권한 644 로 설정
run_fix() { fix_set_owner_perm "/etc/hosts" "root" 644; }
