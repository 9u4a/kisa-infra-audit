# U-04 (상) 비밀번호 파일 보호
# 판단 기준(가이드 원문): 양호 = 쉐도우 비밀번호를 사용하거나 비밀번호를 암호화하여 저장하는 경우
#                        취약 = 쉐도우 비밀번호를 사용하지 않고 비밀번호를 암호화 저장하지 않는 경우
# 자동화 범위: SOLARIS/LINUX 계열 공통 로직 (/etc/passwd 2번째 필드가 모두 'x' 인지 확인).
# AIX/HP-UX 는 비밀번호 저장 위치 자체가 달라(§카테고리 고유 주의사항 - 문서 기준, 미검증)
# 별도 로직으로 판정한다.

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
        aix)
            # AIX는 /etc/security/passwd 에 실제 해시를 저장하고 /etc/passwd 2번째 필드는
            # 관례적으로 "!"(또는 "*")만 남긴다 - 그 외 값이 있으면 구버전 평문/비분리 저장.
            passwd_file="/etc/passwd"; secpw="/etc/security/passwd"
            if [ ! -r "$passwd_file" ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="$passwd_file 를 읽을 수 없음"; CHECK_EVIDENCE=""
                return
            fi
            plain_accounts=$(awk -F: '$2 != "!" && $2 != "*" && length($2) > 0 {print $1":"$2}' "$passwd_file")
            if [ -f "$secpw" ] && [ -z "$plain_accounts" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="$secpw 에 비밀번호가 분리 저장되어 있으며 $passwd_file 에 평문/해시 필드가 없음"
                CHECK_EVIDENCE="$secpw 존재, $passwd_file 2번째 필드 전부 '!'/'*'"
            elif [ -n "$plain_accounts" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="$passwd_file 에 비밀번호가 분리 저장되지 않은 것으로 보이는 계정이 존재함"
                CHECK_EVIDENCE="$plain_accounts"
            else
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="$secpw 파일이 없어 비밀번호 분리 저장 여부 확인 불가"
                CHECK_EVIDENCE=""
            fi
            ;;
        hpux)
            # HP-UX 는 Trusted Mode(/tcb/files/auth/* 로 완전 분리) 또는 표준 모드 shadow
            # (/etc/shadow, pwconv 로 활성화) 중 하나라도 쓰면 양호로 본다.
            passwd_file="/etc/passwd"; tcb="/tcb/files/auth"
            if [ ! -r "$passwd_file" ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="$passwd_file 를 읽을 수 없음"; CHECK_EVIDENCE=""
                return
            fi
            if [ -d "$tcb" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="Trusted Mode($tcb)가 활성화되어 있어 비밀번호가 완전히 분리 저장됨"
                CHECK_EVIDENCE="$tcb 디렉터리 존재"
                return
            fi
            plain_accounts=$(awk -F: '$2 != "x" && $2 != "*" && length($2) > 0 {print $1":"$2}' "$passwd_file")
            if [ -f /etc/shadow ] && [ -z "$plain_accounts" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="표준 모드 쉐도우(/etc/shadow) 사용 중이며 $passwd_file 에 평문 비밀번호 필드가 없음"
                CHECK_EVIDENCE="/etc/shadow 존재"
            elif [ -n "$plain_accounts" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="Trusted Mode 미사용 + 쉐도우 처리되지 않은 것으로 보이는 계정이 존재함"
                CHECK_EVIDENCE="$plain_accounts"
            else
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="Trusted Mode·쉐도우 사용 여부를 확인할 근거를 찾지 못함"
                CHECK_EVIDENCE=""
            fi
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}
