# U-18 (상) /etc/shadow 파일 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 소유자 root, 권한 400 이하 / 취약 = 그 외
# 자동화 범위: Linux/Solaris (/etc/shadow). AIX는 /etc/security/passwd, HP-UX는 Trusted Mode면
# /tcb/files/auth 디렉터리 자체, 아니면 /etc/shadow (문서 기준, 미검증).

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris)
            check_owner_perm "/etc/shadow" "root" 400
            ;;
        aix)
            check_owner_perm "/etc/security/passwd" "root" 600
            ;;
        hpux)
            if [ -d /tcb/files/auth ]; then
                check_owner_perm "/tcb/files/auth" "root" 700
            else
                check_owner_perm "/etc/shadow" "root" 400
            fi
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}
