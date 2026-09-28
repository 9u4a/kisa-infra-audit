# U-04 (상) 비밀번호 파일 보호
# 판단 기준(가이드 원문): 양호 = 쉐도우 비밀번호를 사용하거나 비밀번호를 암호화하여 저장하는 경우
#                        취약 = 쉐도우 비밀번호를 사용하지 않고 비밀번호를 암호화 저장하지 않는 경우
# 자동화 범위: SOLARIS/LINUX 계열 공통 로직 (/etc/passwd 2번째 필드가 모두 'x' 인지 확인).

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris)
            passwd_file="/etc/passwd"
            if [ ! -r "$passwd_file" ]; then
                CHECK_STATUS="ERROR"
                CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
                CHECK_EVIDENCE=""
                return
            fi
            plain_accounts=$(awk -F: '$2 != "x" && $2 != "*" && $2 != "!" && length($2) > 0 {print $1":"$2}' "$passwd_file")
            if [ -f /etc/shadow ] && [ -z "$plain_accounts" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="쉐도우 비밀번호 사용 중이며 /etc/passwd 에 평문 비밀번호 필드가 없음"
                CHECK_EVIDENCE="/etc/shadow 존재, /etc/passwd 2번째 필드 전부 'x'"
            elif [ -n "$plain_accounts" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="/etc/passwd 에 쉐도우 처리되지 않은 것으로 보이는 계정이 존재함"
                CHECK_EVIDENCE="$plain_accounts"
            else
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="/etc/shadow 파일이 없어 쉐도우 사용 여부 확인 불가"
                CHECK_EVIDENCE=""
            fi
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현 (0.2.0에서 AIX/HP-UX 지원 예정)"
            CHECK_EVIDENCE=""
            ;;
    esac
}
