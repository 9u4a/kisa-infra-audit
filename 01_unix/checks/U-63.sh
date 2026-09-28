# U-63 (중) sudo 명령어 접근 관리
# 판단 기준(가이드 원문): 양호 = /etc/sudoers 소유자 root, 권한 640(이하) / 취약 = 그 외
# 전 Unix 계열 공통 로직. sudo 미사용(파일 없음) 시 NA.

run_check() {
    check_owner_perm "/etc/sudoers" "root" 640
}
