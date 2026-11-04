# U-16 (상) /etc/passwd 파일 소유자 및 권한 설정 — 조치
# 변경: /etc/passwd 소유자 root·권한 644 로 설정
run_fix() { fix_set_owner_perm "/etc/passwd" "root" 644; }
