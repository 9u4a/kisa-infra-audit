# U-06 (상) 사용자 계정 su 기능 제한
# 판단 기준(가이드 원문): 양호 = su 명령어를 특정 그룹(wheel 등)에 속한 사용자만 사용하도록 제한된 경우
#                        취약 = su 명령어를 모든 사용자가 사용하도록 설정된 경우
# 자동화 범위: LINUX(rhel/debian) 의 PAM(pam_wheel.so) 방식만 판정.

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
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}
