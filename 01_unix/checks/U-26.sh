# U-26 (상) /dev에 존재하지 않는 device 파일 점검
# 판단 기준(가이드 원문): 양호 = /dev 점검 후 존재하지 않는(major/minor 번호가 없는) device 파일을
#                        제거한 경우 / 취약 = 미점검 또는 방치한 경우
# 참고: 가이드 원문 상 이 항목의 "점검 내용/점검 목적/보안 위협" 문단은 원본 PDF 자체의 편집 오류로
#       U-28(접속 IP/포트 제한)의 문구가 잘못 들어가 있다(제목·판단기준·조치방법은 device 파일이
#       맞음, PDF p.53 원문 확인됨). guide.json/guide.md 는 원문을 그대로 보존하고, 이 check는
#       제목·판단기준·조치방법 기준으로 구현한다.
# 전 Unix 계열 공통 로직: /dev 내 일반 파일(= major/minor 번호가 없는 위장 파일)을 탐지.

run_check() {
    if [ ! -d /dev ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="/dev 디렉터리를 찾을 수 없음"
        CHECK_EVIDENCE=""
        return
    fi

    # /dev/mqueue, /dev/shm 은 가이드에서 명시적으로 예외 처리
    fake=$(find /dev -xdev -type f \
        -not -path '/dev/mqueue/*' -not -path '/dev/shm/*' \
        2>/dev/null | head -n 50)

    if [ -z "$fake" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="/dev 디렉터리 내 major/minor 번호가 없는(존재하지 않는) device 파일이 없음"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="/dev 디렉터리 내 일반 파일(위장 가능성 있는 device 파일)이 존재함"
        CHECK_EVIDENCE="$(printf '%s\n' "$fake" | xargs ls -l 2>/dev/null)"
    fi
}
