# U-32 (중) 홈 디렉토리로 지정한 디렉토리의 존재 관리
# 판단 기준(가이드 원문): 양호 = 홈 디렉토리가 존재하지 않는 계정이 발견되지 않는 경우
#                        취약 = 발견된 경우
# 전 Unix 계열 공통 로직. 단, nologin/false 쉘 + 홈이 "/", "/nonexistent" 등 의도적 더미값인
# 표준 서비스 계정(nobody 등)은 관례적으로 정상이므로 제외한다.

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    missing=""
    while IFS=: read -r name _ _ _ _ home shell; do
        [ -z "$name" ] && continue
        case "$home" in
            /|/nonexistent|/nonexisting) continue ;;
        esac
        case "$shell" in
            */nologin|/bin/false) [ "$home" = "" ] && continue ;;
        esac
        [ -d "$home" ] && continue
        missing="$missing
$name:$home"
    done < "$passwd_file"

    if [ -z "$missing" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="홈 디렉토리가 존재하지 않는 계정이 발견되지 않음"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="/etc/passwd 에 지정된 홈 디렉토리가 실제로 존재하지 않는 계정이 있음"
        CHECK_EVIDENCE="$missing"
    fi
}
