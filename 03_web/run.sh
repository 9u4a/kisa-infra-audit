#!/bin/sh
# 03_web/run.sh — 웹 서비스(Apache/Nginx/Tomcat) 진단 진입점 (POSIX sh)
#
# 옵션 문자는 전 카테고리와 통일한다 (루트 CLAUDE.md "CLI 옵션 문자 통일" 참고): -l -i -g -e -o -h
#
# 사용법:
#   run.sh                  설치된 엔진 자동 탐지 후 전체 항목 일괄 진단 (여러 엔진 동시 가능)
#   run.sh -i WEB-01,WEB-04 개별(복수) 항목만 진단
#   run.sh -g 2             하위분류 단위(1=계정관리 ... 4=패치및로그관리) 진단
#   run.sh -e nginx         특정 엔진으로 제한 (apache|nginx|tomcat)
#   run.sh -l               항목 목록만 출력
#   run.sh -o <dir>         결과 출력 경로 지정 (기본: ../output)
#
# IIS 는 별도로 run.ps1 을 사용한다. 이 스크립트는 대상 설정을 변경하지 않는다 (진단 전용).

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/../lib"
GUIDE_JSON="$SCRIPT_DIR/guide.json"
CATEGORY_NUM="03"
CATEGORY_NAME="웹 서비스"

# shellcheck disable=SC1090
. "$LIB_DIR/common.sh"

if [ ! -f "$GUIDE_JSON" ]; then
    echo "오류: $GUIDE_JSON 이 없습니다. lib/extract_guide.py 를 먼저 실행하세요." >&2
    exit 2
fi

ITEM_FILTER=""
GROUP_FILTER=""
ENGINE_OVERRIDE=""
OUT_BASE="$SCRIPT_DIR/../output"
LIST_ONLY=0

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -i) ITEM_FILTER=$2; shift 2 ;;
        -g) GROUP_FILTER=$2; shift 2 ;;
        -e) ENGINE_OVERRIDE=$2; shift 2 ;;
        -o) OUT_BASE=$2; shift 2 ;;
        -l) LIST_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
    esac
done

ALL_CODES=$(guide_list_codes "$GUIDE_JSON")

if [ "$LIST_ONLY" -eq 1 ]; then
    printf '%-8s %-4s %-8s %s\n' "코드" "중요도" "분류" "항목명"
    for code in $ALL_CODES; do
        title=$(guide_field "$GUIDE_JSON" "$code" "title")
        sev=$(guide_field "$GUIDE_JSON" "$code" "severity")
        gno=$(guide_field "$GUIDE_JSON" "$code" "group_no")
        printf '%-8s %-4s %-8s %s\n' "$code" "$sev" "$gno" "$title"
    done
    exit 0
fi

if [ -n "$ENGINE_OVERRIDE" ]; then
    WEB_ENGINES="$ENGINE_OVERRIDE"
else
    detect_web_engines
fi

SELECTED=""
if [ -n "$ITEM_FILTER" ]; then
    _old_ifs=$IFS; IFS=,
    for code in $ITEM_FILTER; do SELECTED="$SELECTED $code"; done
    IFS=$_old_ifs
elif [ -n "$GROUP_FILTER" ]; then
    for code in $ALL_CODES; do
        gno=$(guide_field "$GUIDE_JSON" "$code" "group_no")
        [ "$gno" = "$GROUP_FILTER" ] && SELECTED="$SELECTED $code"
    done
else
    SELECTED="$ALL_CODES"
fi

TOTAL=$(echo "$SELECTED" | wc -w | tr -d ' ')
if [ "$TOTAL" -eq 0 ]; then
    log_error "대상 항목이 없습니다."
    exit 2
fi

prepare_output_dir "$OUT_BASE" "$CATEGORY_NUM"
NDJSON="$OUT_DIR/.result.ndjson"
: > "$NDJSON"
CSV_FILE="$OUT_DIR/result.csv"
csv_init "$CSV_FILE"
HOST_NAME=$(hostname 2>/dev/null || echo unknown)

echo "${C_BOLD}=== 주요정보통신기반시설 자동 진단 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
echo "카테고리   : $CATEGORY_NAME"
echo "호스트     : $HOST_NAME"
echo "감지된 엔진: ${WEB_ENGINES:-없음}"
echo "대상 항목  : ${TOTAL}개"
echo "시작 시각  : $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------------------------------------"
log_to_file "진단 시작: 엔진=${WEB_ENGINES:-없음} 대상=$TOTAL 항목"

N_VULN=0; N_MANUAL=0; N_ERROR=0; N_NA=0; N_GOOD=0
_n=0
for code in $SELECTED; do
    _n=$((_n + 1))
    title=$(guide_field "$GUIDE_JSON" "$code" "title")
    sev=$(guide_field "$GUIDE_JSON" "$code" "severity")
    gno=$(guide_field "$GUIDE_JSON" "$code" "group_no")
    check_file="$SCRIPT_DIR/checks/$code.sh"

    CHECK_STATUS="ERROR"
    CHECK_DETAIL="check 스크립트 없음 (미구현 항목)"
    CHECK_EVIDENCE=""

    if [ -f "$check_file" ]; then
        # shellcheck disable=SC1090
        . "$check_file"
        if command -v run_check >/dev/null 2>&1; then
            run_check
        fi
        unset -f run_check 2>/dev/null || true
    fi

    progress_show "$_n" "$TOTAL" "$code" "$title" "$CHECK_STATUS"
    log_to_file "$code [$CHECK_STATUS] $CHECK_DETAIL"
    result_add "$NDJSON" "$code" "$CHECK_STATUS" "$CHECK_DETAIL" "$CHECK_EVIDENCE"
    csv_add "$CSV_FILE" "$code" "$sev" "$gno" "$title" "$CHECK_STATUS" "$CHECK_DETAIL"
    if [ -n "$CHECK_EVIDENCE" ]; then
        printf '%s\n' "$CHECK_EVIDENCE" > "$OUT_DIR/raw/$code.txt"
    fi

    case "$CHECK_STATUS" in
        VULN) N_VULN=$((N_VULN + 1)) ;;
        MANUAL) N_MANUAL=$((N_MANUAL + 1)) ;;
        ERROR) N_ERROR=$((N_ERROR + 1)) ;;
        NA) N_NA=$((N_NA + 1)) ;;
        GOOD) N_GOOD=$((N_GOOD + 1)) ;;
    esac
done

RESULT_JSON="$OUT_DIR/result.json"
result_finalize "$NDJSON" "$RESULT_JSON" "$CATEGORY_NAME" "$HOST_NAME" "${WEB_ENGINES:-none}"
rm -f "$NDJSON"

render_report_html "$LIB_DIR" "$GUIDE_JSON" "$RESULT_JSON" "$OUT_DIR/report.html"
write_summary "$OUT_DIR/summary.txt" "$CATEGORY_NAME" "$HOST_NAME" "${WEB_ENGINES:-none}" "$N_VULN" "$N_MANUAL" "$N_ERROR" "$N_NA" "$N_GOOD"

echo "----------------------------------------------------------------------"
cat "$OUT_DIR/summary.txt"
echo "----------------------------------------------------------------------"
echo "결과 경로: $OUT_DIR"
