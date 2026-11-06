#!/bin/sh
# 01_unix/fix.sh — Unix 서버 자동 조치 진입점 (POSIX sh)
#
# run.sh(진단)와 완전히 분리된 진입점이다. run.sh 는 대상 설정을 절대 바꾸지 않지만, 이
# 스크립트는 실제로 시스템을 변경한다 — 항상 dry-run(기본값)으로 먼저 확인하고, 적용 전
# 자동 백업, 적용 직후 재검증(양호 전환 확인), 실패 시 자동 원복을 수행한다.
#
# 사용법:
#   fix.sh -r <result.json>                     dry-run: 적용 대상·등급만 출력, 아무 것도 바꾸지 않음
#   fix.sh -r <result.json> -i U-01,U-02 --apply  지정 항목만 실제 적용
#   fix.sh -r <result.json> -e debian ...       환경 수동 지정(자동 감지 실패 시 필수)
#   fix.sh -r <result.json> --apply --yes       적용 전 변경 목록 확인(1회)을 생략(confirm 등급은 항상 개별 y/N)
#   fix.sh -r <result.json> --apply --force     result.json 의 호스트·카테고리 불일치·7일 경과 확인을 무시(X-06)
#   fix.sh --rollback <output/host_01_fix_TS 디렉터리>   백업에서 원복
#
# guide.json 의 fix 등급: auto(영향 없음, 즉시 적용) / confirm(서비스 영향 가능, 항목별 확인
# 필수) / manual(정책 판단 필요, 자동 조치 없음 — 가이드 조치 방법만 안내).

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/../lib"
GUIDE_JSON="$SCRIPT_DIR/guide.json"
CATEGORY_NUM="01"
CATEGORY_NAME="Unix 서버"

# shellcheck disable=SC1090
. "$LIB_DIR/common.sh"

RESULT_JSON=""
ITEM_FILTER=""
APPLY=0
YES=0
FORCE=0
ROLLBACK_DIR=""
ENV_OVERRIDE=""
OUT_BASE="$SCRIPT_DIR/../output"

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    # 값이 필요한 옵션을 값 없이 주면 set -u 오류(parameter not set)로 죽었다(실무 적용 검증 P-24) - 사용법 오류로 끝낸다
    case "$1" in -r|-i|-o|-e|--rollback) [ $# -ge 2 ] || { echo "오류: $1 옵션에 값이 필요합니다 (-h 로 사용법 확인)" >&2; exit 2; } ;; esac
    case "$1" in
        -r) RESULT_JSON=$2; shift 2 ;;
        -i) ITEM_FILTER=$2; shift 2 ;;
        -o) OUT_BASE=$2; shift 2 ;;
        -e) ENV_OVERRIDE=$2; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --yes) YES=1; shift ;;
        --force) FORCE=1; shift ;;
        --rollback) ROLLBACK_DIR=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
    esac
done

# 실제로 바꾸는 경우(적용/원복)에만: root 확인 + 동시 실행 잠금(lib/common.sh, 운영 안전 기준 F1/F6)
if [ "$APPLY" -eq 1 ] || [ -n "$ROLLBACK_DIR" ]; then
    fix_require_root
    fix_lock_acquire "$OUT_BASE" "$CATEGORY_NUM"
    trap 'fix_lock_release' EXIT
    trap 'exit 130' INT TERM
    # 실무 적용 검증 P-19: SSH 가 끊겨도(HUP) 조치 도중 죽지 않게 HUP 은 무시한다 - 진행 중인 항목은 재검증·원복까지 끝나고, 터미널이
    # 없어진 뒤의 확인(confirm)은 읽기 실패로 거부 처리된다. 무시("")한 트랩은 항목 서브셸(run_fix_isolated)에도 물려진다.
    trap '' HUP
fi

if [ -n "$ROLLBACK_DIR" ]; then
    fix_rollback_all "$ROLLBACK_DIR"
    exit $?
fi

if [ -z "$RESULT_JSON" ] || [ ! -f "$RESULT_JSON" ]; then
    echo "오류: -r <result.json> 이 필요합니다 (run.sh 진단 결과 파일)." >&2
    usage
    exit 2
fi
if [ ! -f "$GUIDE_JSON" ]; then
    echo "오류: $GUIDE_JSON 이 없습니다." >&2
    exit 2
fi

# OS 계열 감지(run.sh 와 동일). 예전에는 여기서 OS_FAMILY 를 정하지 않아, 1.1.0 에서 조치 결과에
# unverified_note($OS_FAMILY 참조)를 붙인 뒤로 set -u 때문에 첫 항목에서 "parameter not set"으로
# fix.sh 전체가 죽었다(1.2.2 에서 발견). 조치는 환경을 추측하면 안 되므로 감지 실패 시 -e 를 요구한다.
if [ -n "$ENV_OVERRIDE" ]; then
    OS_FAMILY="$ENV_OVERRIDE"
else
    detect_os_family
    if [ "$OS_FAMILY" = "unknown" ]; then
        log_error "환경을 자동으로 감지하지 못했습니다. -e <rhel|debian|suse|solaris|aix|hpux> 로 지정하세요(변경 없음)."
        exit 2
    fi
fi
export OS_FAMILY

# X-06(1.3.4): 이 호스트·카테고리의 진단 결과인지, 너무 오래되지 않았는지 확인(불일치는 --force 없이는 exit 2).
# 카테고리 이름은 run.sh 의 CATEGORY_NAME(result.json "category")과 같은 값이어야 한다
fix_check_result_target "$RESULT_JSON" "UNIX"

fix_select_vuln_codes

# shellcheck disable=SC2086
FIX_FILE_DIR="$SCRIPT_DIR/fixes"
[ "$APPLY" -eq 1 ] && fix_confirm_plan $VULN_CODES

fix_prepare_dir "$OUT_BASE" "$CATEGORY_NUM"
export FIX_BACKUP_DIR

echo "${C_BOLD}=== 자동 조치 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
echo "카테고리   : $CATEGORY_NAME"
echo "모드       : $([ "$APPLY" -eq 1 ] && echo '실제 적용' || echo 'DRY-RUN (미리보기만, 아무 것도 바꾸지 않음)')"
echo "대상 항목  : ${TOTAL}개 (진단 결과 중 VULN$( [ -n "$ITEM_FILTER" ] && echo ", -i 필터 적용"))"
echo "------------------------------------------------------------------------"

# Solaris/AIX/HP-UX 는 실기 검증 불가 환경이라 조치 결과·재검증에도 "미검증" 안내를 남긴다(lib/common.sh unverified_note).
unix_post_fix() { FIX_DETAIL="${FIX_DETAIL}$(unverified_note)"; }
fix_items "$SCRIPT_DIR/fixes" "$SCRIPT_DIR/checks" unix_post_fix append_unverified_note

fix_print_summary "$0"
