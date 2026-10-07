# U-06 (상) 사용자 계정 su 기능 제한
# 판단 기준(가이드 원문): 양호 = su 명령어를 특정 그룹(wheel 등)에 속한 사용자만 사용하도록 제한된 경우
#                        취약 = su 명령어를 모든 사용자가 사용하도록 설정된 경우
# 자동화 범위: LINUX(rhel/debian) 의 PAM(pam_wheel.so) 방식으로 판정.
# Solaris/AIX/HP-UX 는 PAM wheel 모듈을 기본 제공하지 않는 경우가 많아, 더 전통적인 Unix
# 방식인 "su 바이너리 자체의 실행 권한"(그룹 소유 + other 실행 비트 제거)으로 판정한다
# (문서 기준, 미검증).

_u06_check_binary_perm() {
    _su_bin=""
    for _p in /usr/bin/su /bin/su /usr/sbin/su; do
        [ -x "$_p" ] && _su_bin="$_p" && break
    done
    if [ -z "$_su_bin" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="su 바이너리 경로를 찾지 못해 자동 판정 불가"; CHECK_EVIDENCE=""
        return
    fi
    _ls=$(ls -lL "$_su_bin" 2>/dev/null)
    _mode=$(printf '%s' "$_ls" | awk '{print $1}')
    _group=$(printf '%s' "$_ls" | awk '{print $4}')
    _other_x=$(printf '%s' "$_mode" | cut -c10)
    if [ "$_other_x" = "-" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="$_su_bin 가 other 실행 권한 없이(그룹 '$_group'만 실행 가능) 설정되어 su 사용이 제한됨"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="$_su_bin 에 other 실행 권한이 있어 모든 사용자가 su 를 사용할 수 있음"
    fi
    CHECK_EVIDENCE="$_ls"
}

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse)
            pam_su="/etc/pam.d/su"
            if [ ! -f "$pam_su" ]; then
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="$pam_su 파일을 찾을 수 없어 자동 판정 불가"
                CHECK_EVIDENCE=""
                return
            fi
            line=$(grep -E '^[[:space:]]*auth[[:space:]]+(required|requisite|sufficient)[[:space:]]+pam_wheel\.so' "$pam_su" 2>/dev/null | head -n1)
            if [ -n "$line" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="pam_wheel.so 모듈이 활성화되어 su 사용이 특정 그룹으로 제한됨"
            else
                CHECK_STATUS="VULN"
                CHECK_DETAIL="$pam_su 에 pam_wheel.so 활성화 설정이 없어 모든 사용자가 su 를 사용할 수 있음"
            fi
            CHECK_EVIDENCE="$pam_su:
${line:-(pam_wheel.so 관련 활성 라인 없음)}"
            ;;
        solaris|aix|hpux)
            _u06_check_binary_perm
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}
