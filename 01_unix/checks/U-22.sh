# U-22 (상) /etc/services 파일 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 소유자 root(또는 bin, sys), 권한 644 이하 / 취약 = 그 외
# 전 Unix 계열 공통 로직.

run_check() {
    check_owner_perm "/etc/services" "root bin sys" 644
}
