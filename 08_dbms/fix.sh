#!/bin/sh
# 08_dbms/fix.sh — DBMS(MySQL/PostgreSQL/Oracle) 자동 조치 진입점 (POSIX sh)
#
# run.sh(진단)와 완전히 분리된 진입점이다. MSSQL 대상은 별도 08_dbms/fix.ps1(PowerShell)을
# 사용한다. 01_unix/fix.sh 와 완전히 동일한 흐름·CLI를 쓴다(dry-run 기본, --apply/--apply --yes/
# --rollback). DB 상태 변경은 파일이 아니라 SQL 실행 결과라 fix_db_queue_rollback 으로 원복용
# SQL 을 큐에 넣어두고 --rollback 시 재실행한다(lib/common.sh 참고).
#
# 접속 정보는 run.sh 와 동일하게 --host/--port/--user/--db 로 지정하고, 비밀번호는 DB_PASSWORD
# 환경변수로만 전달한다.
#
# 사용법:
#   fix.sh -e mysql -r <result.json>                       dry-run: 적용 대상·등급만 출력
#   fix.sh -e mysql -r <result.json> -i D-01,D-05 --apply   지정 항목만 실제 적용
#   fix.sh -e mysql -r <result.json> --apply --yes          적용 전 변경 목록 확인(1회) 생략(confirm 은 항상 개별 y/N)
#   fix.sh -e mysql -r <result.json> --apply --force        result.json 의 호스트·카테고리·엔진 불일치·7일 경과 확인을 무시(X-06)
#   fix.sh -e mysql -r <result.json> --policy <정책 파일> --operator <실행자> [--apply]
#                                                          정책 모드(무인): 승인 항목만 확인 없이 적용, 감사 기록(audit.txt)
#   fix.sh -e mysql --rollback <output/host_08_fix_TS 디렉터리>  백업에서 원복

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/../lib"
GUIDE_JSON="$SCRIPT_DIR/guide.json"
CATEGORY_NUM="08"
CATEGORY_NAME="DBMS"

# shellcheck disable=SC1090
. "$LIB_DIR/common.sh"

RESULT_JSON=""
ITEM_FILTER=""
ENGINE_OVERRIDE=""
APPLY=0
YES=0
FORCE=0
ROLLBACK_DIR=""
OUT_BASE="$SCRIPT_DIR/../output"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    # 값이 필요한 옵션을 값 없이 주면 set -u 오류(parameter not set)로 죽었다(실무 적용 검증 P-24) - 사용법 오류로 끝낸다
    case "$1" in -r|-i|-e|-o|--rollback|--host|--port|--user|--db|--socket|--policy|--operator) [ $# -ge 2 ] || { echo "오류: $1 옵션에 값이 필요합니다 (-h 로 사용법 확인)" >&2; exit 2; } ;; esac
    case "$1" in
        -r) RESULT_JSON=$2; shift 2 ;;
        -i) ITEM_FILTER=$2; shift 2 ;;
        -e) ENGINE_OVERRIDE=$2; shift 2 ;;
        -o) OUT_BASE=$2; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --yes) YES=1; shift ;;
        --force) FORCE=1; shift ;;
        --rollback) ROLLBACK_DIR=$2; shift 2 ;;
        --policy) POLICY_SET=1; POLICY_FILE=$2; shift 2 ;;
        --operator) POLICY_OPERATOR_SET=1; POLICY_OPERATOR=$2; shift 2 ;;
        --host) DB_HOST=$2; shift 2 ;;
        --port) DB_PORT=$2; shift 2 ;;
        --user) DB_USER=$2; shift 2 ;;
        --db) DB_NAME=$2; shift 2 ;;
        --socket) DB_SOCKET=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
    esac
done

# 1.6.0 G-01: --policy/--operator 조합 확인(잘못되면 변경 없이 exit 2)
fix_policy_args_check "$ROLLBACK_DIR"

if [ -z "$ENGINE_OVERRIDE" ]; then
    echo "오류: -e mysql|postgres|oracle 로 엔진을 지정해야 합니다(MSSQL은 fix.ps1 사용)." >&2
    usage
    exit 2
fi
DBMS_ENGINE="$ENGINE_OVERRIDE"

# 1.6.0 G-01: 정책 파일 검증(카테고리·유효기간·호스트·코드) - 거부될 실행으로 DB 에 접속하지 않도록 사전 접속 점검보다 먼저
fix_policy_load

DB_ERR_FILE=$(mktemp 2>/dev/null) || {
    DB_ERR_FILE="${TMPDIR:-/tmp}/.dbms_fix_err.$$"
    ( umask 077; set -C; : > "$DB_ERR_FILE" ) 2>/dev/null || { echo "오류: 임시 파일을 만들 수 없습니다: $DB_ERR_FILE" >&2; exit 2; }
}
trap 'rm -f "$DB_ERR_FILE"; fix_lock_release' EXIT
trap 'exit 130' INT TERM
# 실무 적용 검증 P-19: SSH 가 끊겨도(HUP) 조치 도중 죽지 않게 HUP 은 무시한다 - 진행 중인 항목은 재검증·원복까지 끝나고, 터미널이
# 없어진 뒤의 확인(confirm)은 읽기 실패로 거부 처리된다. 무시("")한 트랩은 항목 서브셸(run_fix_isolated)에도 물려진다.
trap '' HUP
export DB_HOST DB_PORT DB_USER DB_NAME DB_SOCKET DB_ERR_FILE DBMS_ENGINE

# 동시 실행 잠금(lib/common.sh). root 필수 가드는 쓰지 않는다 - Oracle OS 인증("/ as sysdba")은
# oracle 계정/dba 그룹으로 실행해야 하고, 대부분의 조치가 SQL 이라 root 가 필요 없다.
if [ "$APPLY" -eq 1 ] || [ -n "$ROLLBACK_DIR" ]; then
    fix_lock_acquire "$OUT_BASE" "$CATEGORY_NUM"
fi

# 적용/원복은 항목마다 DB에 접속하므로, 잘못된 접속 정보로 로그인 실패를 반복해 계정이 잠기기
# 전에 1회만 시험하고 실패하면 아무것도 바꾸지 않고 중단한다.
if [ "$APPLY" -eq 1 ] || [ -n "$ROLLBACK_DIR" ]; then
    if ! db_preflight; then
        echo "오류: DB 접속 사전 점검 실패 - 계정 잠금 방지를 위해 재시도하지 않고 중단합니다(변경 없음): $DB_CONN_FAIL_MSG" >&2
        exit 2
    fi
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

# X-06(1.3.4): 이 호스트·카테고리·엔진의 진단 결과인지, 너무 오래되지 않았는지 확인(불일치는 --force 없이는 exit 2).
# 카테고리 이름은 run.sh 의 CATEGORY_NAME(result.json "category")과 같은 값이어야 한다
fix_check_result_target "$RESULT_JSON" "DBMS" "$DBMS_ENGINE"

fix_select_vuln_codes

# shellcheck disable=SC2086
FIX_FILE_DIR="$SCRIPT_DIR/fixes/$DBMS_ENGINE"
[ "$APPLY" -eq 1 ] && fix_confirm_plan $VULN_CODES

fix_prepare_dir "$OUT_BASE" "$CATEGORY_NUM"
export FIX_BACKUP_DIR

echo "${C_BOLD}=== 자동 조치 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
echo "카테고리   : $CATEGORY_NAME (엔진: $DBMS_ENGINE — MSSQL은 fix.ps1 사용)"
echo "모드       : $([ "$APPLY" -eq 1 ] && echo '실제 적용' || echo 'DRY-RUN (미리보기만, 아무 것도 바꾸지 않음)')"
echo "대상 항목  : ${TOTAL}개 (진단 결과 중 VULN$( [ -n "$ITEM_FILTER" ] && echo ", -i 필터 적용"))"
fix_policy_banner
echo "------------------------------------------------------------------------"

fix_items "$SCRIPT_DIR/fixes/$DBMS_ENGINE" "$SCRIPT_DIR/checks/$DBMS_ENGINE"

fix_print_summary "$0 -e $DBMS_ENGINE"
