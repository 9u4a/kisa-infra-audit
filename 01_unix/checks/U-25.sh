# U-25 (상) world writable 파일 점검
# 판단 기준(가이드 원문): 양호 = world writable 파일이 없거나, 있어도 설정 이유를 인지하고 있는 경우
#                        취약 = 있으나 이유를 인지하지 못하는 경우
# "이유 인지 여부"는 기계적으로 판단할 수 없으므로: 파일이 없으면 GOOD, 있으면 목록을 제시하고
# MANUAL 로 응답한다 (관리자가 각 항목의 필요성을 검토).

run_check() {
    if ! command -v find >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="find 명령을 사용할 수 없음"
        CHECK_EVIDENCE=""
        return
    fi

    # root 가 아니면 읽을 수 없는 디렉터리가 조용히 빠져 목록이 불완전해진다.
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="파일시스템 전수 검색은 root 권한이 필요함(권한 부족 시 결과가 누락되어 판정 불가)"; CHECK_EVIDENCE=""
        return
    fi
    files=$(low_prio find / -xdev -type f -perm -0002 2>/dev/null | head -n 100)
    excluded=$(scan_excluded_mounts)

    if [ -z "$files" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="world writable 파일이 존재하지 않음${excluded:+ (루트 파일시스템 기준 - 별도 파일시스템 미검색: $excluded)}"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="world writable 파일이 존재함(최대 100건). 각 파일의 설정 사유를 인지하고 있는지 수동 검토 필요${excluded:+ (별도 파일시스템 미검색: $excluded)}"
        CHECK_EVIDENCE="$(printf '%s\n' "$files" | xargs ls -al 2>/dev/null)"
    fi
}
