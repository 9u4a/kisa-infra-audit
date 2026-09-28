# U-67 (중) 로그 디렉터리 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리 내 로그 파일의 소유자가 root이고 권한이 644 이하
#                        취약 = 소유자가 root가 아니거나 권한이 644를 초과하는 경우
# 자동화 범위: LINUX/SOLARIS 기준 /var/log. AIX(/var/adm), HP-UX(/var/adm/syslog)는 MANUAL.

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris)
            log_dir="/var/log"
            if [ ! -d "$log_dir" ]; then
                CHECK_STATUS="ERROR"
                CHECK_DETAIL="$log_dir 디렉터리를 찾을 수 없음"
                CHECK_EVIDENCE=""
                return
            fi
            bad=$(find "$log_dir" -maxdepth 1 -type f \( ! -user root -o -perm -0133 \) 2>/dev/null | head -n 30)
            if [ -z "$bad" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="$log_dir 내 최상위 로그 파일이 모두 root 소유이며 권한이 644 이하임"
                CHECK_EVIDENCE=""
            else
                CHECK_STATUS="VULN"
                CHECK_DETAIL="$log_dir 내 소유자가 root가 아니거나 권한이 644를 초과하는 로그 파일이 존재함 (최대 30건)"
                CHECK_EVIDENCE="$(printf '%s\n' "$bad" | xargs ls -l 2>/dev/null)"
            fi
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현 (AIX: /var/adm, HP-UX: /var/adm/syslog)"
            CHECK_EVIDENCE=""
            ;;
    esac
}
