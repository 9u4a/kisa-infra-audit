#!/bin/sh
# 03_web/run.sh — 웹 서비스(Apache/Nginx/Tomcat) 진단 진입점 (POSIX sh)
#
# 옵션 문자는 전 카테고리와 통일한다: -l -i -g -e -o -h
#
# 사용법:
#   run.sh                  설치된 엔진 자동 탐지 후 전체 항목 일괄 진단 (여러 엔진 동시 가능)
#   run.sh -i WEB-01,WEB-04 개별(복수) 항목만 진단
#   run.sh -g 2             하위분류 단위(1=계정관리 ... 4=패치및로그관리) 진단
#   run.sh -e nginx         특정 엔진으로 제한 (apache|nginx|tomcat, 콤마로 여러 개)
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
    # 값이 필요한 옵션을 값 없이 주면 set -u 오류(parameter not set)로 죽었다(실무 적용 검증 P-24) - 사용법 오류로 끝낸다
    case "$1" in -i|-g|-e|-o) [ $# -ge 2 ] || { echo "오류: $1 옵션에 값이 필요합니다 (-h 로 사용법 확인)" >&2; exit 2; } ;; esac
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

if [ "$LIST_ONLY" -eq 1 ]; then
    run_list_items
    exit 0
fi

# -e 는 각 check 가 다시 탐지하지 않고 그대로 쓴다(detect_web_engines 는 WEB_ENGINES 가 비어 있을 때만 탐지 -
# 진단 검수 WEB-R5). 지원하지 않는 값은 조용히 무시하지 않고 중단한다. 콤마/공백으로 여러 엔진 지정 가능.
WEB_ENGINES=""
if [ -n "$ENGINE_OVERRIDE" ]; then
    for _e in $(printf '%s' "$ENGINE_OVERRIDE" | tr ',' ' '); do
        case "$_e" in
            apache|nginx|tomcat) case " $WEB_ENGINES " in *" $_e "*) ;; *) WEB_ENGINES="${WEB_ENGINES:+$WEB_ENGINES }$_e" ;; esac ;;
            *) echo "오류: 지원하지 않는 엔진: $_e (apache|nginx|tomcat, IIS 는 run.ps1)" >&2; exit 2 ;;
        esac
    done
else
    detect_web_engines
fi

# web_unsupported_note <코드> -- JEUS/WebtoB 처럼 감지는 되지만 자동 진단을 구현하지 않은 엔진이 있으면, 그 엔진이
# 가이드 대상인 항목의 GOOD/NA 를 MANUAL 로 바꾼다(지원 엔진만 보고 "양호/해당없음"이라 하면 거짓 - 진단 검수 WEB-R11).
web_unsupported_note() {
    _wun=""
    _targets=$(guide_field "$GUIDE_JSON" "$1" "targets" | tr 'A-Z' 'a-z')
    case " $WEB_ENGINES " in *" jeus "*) case "$_targets" in *jeus*) _wun="$_wun JEUS" ;; esac ;; esac
    case " $WEB_ENGINES " in *" webtob "*) case "$_targets" in *webtob*) _wun="$_wun WebtoB" ;; esac ;; esac
    [ -n "$_wun" ] || return 0
    case "$CHECK_STATUS" in
        GOOD|NA)
            CHECK_DETAIL="자동 진단을 지원하지 않는 엔진이 감지됨(${_wun# }) - 해당 엔진은 수동 점검 필요 / 지원 엔진 판정: $CHECK_STATUS - $CHECK_DETAIL"
            CHECK_STATUS="MANUAL" ;;
    esac
}

run_select_codes

run_begin_output WEB_ENGINES

echo "${C_BOLD}=== 주요정보통신기반시설 자동 진단 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
[ "$(id -u 2>/dev/null)" != "0" ] && log_warn "root 권한이 아닙니다. 읽지 못한 설정·로그 파일 관련 항목은 ERROR 로 표시됩니다(root 실행 권장)."
echo "카테고리   : $CATEGORY_NAME"
echo "호스트     : $HOST_NAME"
echo "감지된 엔진: ${WEB_ENGINES:-없음}"
# 실무 적용 검증 P-07: Tomcat 인스턴스가 여러 개면 한 번에 하나만 진단한다(lib/common.sh tomcat_home) - 대상과 재실행 방법을 알린다
case " $WEB_ENGINES " in *" tomcat "*)
    _tci=$(tomcat_instances)
    if [ "$(printf '%s\n' "$_tci" | grep -c .)" -gt 1 ]; then
        log_warn "실행 중인 Tomcat 인스턴스가 여러 개입니다. 이번 진단 대상: $(tomcat_home 2>/dev/null || echo 없음). 나머지는 인스턴스마다 CATALINA_BASE=<경로> sh run.sh -e tomcat 으로 따로 진단하세요: $(printf '%s' "$_tci" | tr '\n' ' ')"
        log_to_file "Tomcat 다중 인스턴스: $(printf '%s' "$_tci" | tr '\n' ' ') / 진단 대상: $(tomcat_home 2>/dev/null)"
    fi ;;
esac
echo "대상 항목  : ${TOTAL}개"
echo "시작 시각  : $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------------------------------------"
log_to_file "진단 시작: 엔진=${WEB_ENGINES:-없음} 대상=$TOTAL 항목"

web_item_post() {
    nonroot_unverified
    web_unsupported_note "$1"
}
run_items "$SCRIPT_DIR/checks" ERROR "check 스크립트 없음 (미구현 항목)" web_item_post

run_finish "${WEB_ENGINES:-none}"
