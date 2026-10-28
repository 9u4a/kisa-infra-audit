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
    skipped=""
    while IFS=: read -r name _ _ _ _ home shell; do
        [ -z "$name" ] && continue
        case "$home" in
            /|/nonexistent|/nonexisting) continue ;;
        esac
        case "$shell" in
            */nologin|*/false) [ "$home" = "" ] && continue ;;
        esac
        # 원격/자동마운트 홈은 존재 확인([ -d ])만으로도 마운트를 깨우거나 멈출 수 있어 건너뛴다
        if is_remote_or_auto_fs "$home"; then skipped="$skipped $home"; continue; fi
        [ -d "$home" ] && continue
        missing="$missing
$name:$home"
    done < "$passwd_file"

    if [ -z "$missing" ] && [ -n "$skipped" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="로컬 홈은 모두 존재하나 원격/자동마운트 홈은 운영 영향 방지를 위해 확인하지 않음 - 수동 확인 필요:$skipped"
        CHECK_EVIDENCE=""
    elif [ -z "$missing" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="홈 디렉토리가 존재하지 않는 계정이 발견되지 않음"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="/etc/passwd 에 지정된 홈 디렉토리가 실제로 존재하지 않는 계정이 있음"
        CHECK_EVIDENCE="$missing"
    fi
}
