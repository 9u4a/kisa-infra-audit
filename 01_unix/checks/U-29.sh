# U-29 (하) hosts.lpd 파일 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 파일이 없거나, 있어도 소유자 root/권한 600 이하
#                        취약 = 있고 기준 미충족
# 전 Unix 계열 공통 로직 (check_owner_perm 이 파일 부재 시 이미 GOOD 이 아닌 NA 를 주므로 보정).

run_check() {
    if [ ! -e /etc/hosts.lpd ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="/etc/hosts.lpd 파일이 존재하지 않음"
        CHECK_EVIDENCE=""
        return
    fi
    check_owner_perm "/etc/hosts.lpd" "root" 600
}
