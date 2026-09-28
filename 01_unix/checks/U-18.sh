# U-18 (상) /etc/shadow 파일 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 소유자 root, 권한 400 이하 / 취약 = 그 외
# 자동화 범위: Linux/Solaris (/etc/shadow). AIX(/etc/security/passwd)/HP-UX(/tcb/files/auth)는 MANUAL.

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris)
            check_owner_perm "/etc/shadow" "root" 400
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현 (AIX: /etc/security/passwd, HP-UX: /tcb/files/auth)"
            CHECK_EVIDENCE=""
            ;;
    esac
}
