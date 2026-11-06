#!/bin/sh
# 01_unix/run.sh — Unix 서버 진단 진입점 (POSIX sh)
#
# 사용법:
#   run.sh                  전체 항목 일괄 진단, 환경 자동 감지
#   run.sh -i U-01,U-05     개별(복수) 항목만 진단
#   run.sh -g 1             하위분류 단위(1=계정 관리 등) 진단
#   run.sh -e debian        환경 수동 지정 (rhel|debian|suse|solaris|aix|hpux)
#   run.sh -l               항목 목록만 출력
#   run.sh -o <dir>         결과 출력 경로 지정 (기본: ./output)
#
# 이 스크립트는 대상 시스템 설정을 변경하지 않는다 (진단 전용). 조치는 fix.sh 참고.

# 주의: set -e 는 사용하지 않는다. grep/awk 등 진단 명령은 "미검출"을 정상적으로
# 0건(exit 1)으로 반환하는 경우가 많고, 이를 스크립트 중단으로 취급하면 안 되기 때문이다.
# 각 check 는 자체적으로 CHECK_STATUS=ERROR 를 설정해 실패를 보고한다.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/../lib"
GUIDE_JSON="$SCRIPT_DIR/guide.json"
CATEGORY_NUM="01"
CATEGORY_NAME="UNIX"

# shellcheck disable=SC1090
. "$LIB_DIR/common.sh"

if [ ! -f "$GUIDE_JSON" ]; then
    echo "오류: $GUIDE_JSON 이 없습니다. lib/extract_guide.py 를 먼저 실행하세요." >&2
    exit 2
fi

ITEM_FILTER=""
GROUP_FILTER=""
ENV_OVERRIDE=""
OUT_BASE="$SCRIPT_DIR/../output"
LIST_ONLY=0

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    # 값이 필요한 옵션을 값 없이 주면 set -u 오류(parameter not set)로 죽었다(실무 적용 검증 P-24) - 사용법 오류로 끝낸다
    case "$1" in -i|-g|-e|-o) [ $# -ge 2 ] || { echo "오류: $1 옵션에 값이 필요합니다 (-h 로 사용법 확인)" >&2; exit 2; } ;; esac
    case "$1" in
        -i) ITEM_FILTER=$2; shift 2 ;;
        -g) GROUP_FILTER=$2; shift 2 ;;
        -e) ENV_OVERRIDE=$2; shift 2 ;;
        -o) OUT_BASE=$2; shift 2 ;;
        -l) LIST_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
    esac
done

if [ "$LIST_ONLY" -eq 1 ]; then
    run_list_items
    exit 0
fi

if [ -n "$ENV_OVERRIDE" ]; then
    OS_FAMILY="$ENV_OVERRIDE"
else
    detect_os_family
    if [ "$OS_FAMILY" = "unknown" ]; then
        prompt_os_family
    fi
fi

run_select_codes

run_begin_output OS_FAMILY

banner_start "$CATEGORY_NAME" "$TOTAL"
log_to_file "진단 시작: 환경=$OS_FAMILY 대상=$TOTAL 항목"

# 항목 후처리: 비 root 판정 보정 + Solaris/AIX/HP-UX 는 Docker 등으로 실기 검증할 수 없는 환경이라(lib/common.sh
# append_unverified_note 주석 참고) 판정 결과마다 "미검증" 안내를 덧붙인다 - check 67개에 중복하지 않고 여기서 일괄 처리.
unix_item_post() {
    nonroot_unverified
    append_unverified_note
}
run_items "$SCRIPT_DIR/checks" ERROR "check 스크립트 없음 (미구현 항목)" unix_item_post

run_finish "$OS_FAMILY"
