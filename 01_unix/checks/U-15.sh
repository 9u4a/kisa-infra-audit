# U-15 (상) 파일 및 디렉터리 소유자 설정
# 판단 기준(가이드 원문): 양호 = 소유자가 존재하지 않는 파일 및 디렉터리가 없는 경우
#                        취약 = 존재하는 경우
# 전 Unix 계열 공통 로직. 루트 파일시스템만 검사(-xdev, 가이드 조치 사례와 동일).
# 대상 파일 수가 많은 시스템에서는 시간이 걸릴 수 있음.

run_check() {
    if ! command -v find >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="find 명령을 사용할 수 없음"
        CHECK_EVIDENCE=""
        return
    fi

    result=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | head -n 50)
    count=$(printf '%s\n' "$result" | grep -c .)

    if [ -z "$result" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="소유자 또는 그룹이 존재하지 않는 파일/디렉터리가 없음"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="소유자 또는 그룹이 존재하지 않는 파일/디렉터리가 존재함 (최대 50건 표시)"
        CHECK_EVIDENCE="$result"
    fi
}
