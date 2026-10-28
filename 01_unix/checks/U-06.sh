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
            # 진단 검수 U-R8: 그룹 밖 사용자를 실제로 막는 것은 required/requisite 이면서 deny 가 없는 줄뿐이다.
            # sufficient(…trust)는 그룹 구성원을 무암호 통과시킬 뿐 나머지를 막지 않고, deny 는 반대로 그 그룹만 막는다 -
            # 예전에는 sufficient trust 줄 하나만 있어도 GOOD 이었다. 주석(#) 줄은 ^[[:space:]]*auth 에 맞지 않아 제외.
            all_l=$(grep -E '^[[:space:]]*auth[[:space:]]+[^[:space:]]+[[:space:]]+pam_wheel\.so' "$pam_su" 2>/dev/null)
            line=$(printf '%s\n' "$all_l" | grep -E '^[[:space:]]*auth[[:space:]]+(required|requisite)[[:space:]]+pam_wheel\.so' | grep -vE '[[:space:]]deny([[:space:]]|$)' | head -n1)
            if [ -n "$line" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="pam_wheel.so 모듈이 활성화되어 su 사용이 특정 그룹으로 제한됨"
            elif [ -n "$all_l" ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="$pam_su 의 pam_wheel.so 줄이 sufficient(trust)/deny 등이라 그룹 밖 사용자의 su 를 막지 않음"
                line="$all_l"
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
