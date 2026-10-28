#!/bin/sh
# 08_dbms/run.sh — DBMS(MySQL/PostgreSQL/Oracle 등) 진단 진입점 (POSIX sh)
#
# 옵션 문자는 전 카테고리와 통일한다 (루트 CLAUDE.md "CLI 옵션 문자 통일" 참고): -l -i -g -e -o -h
# 접속 정보는 --host/--port/--user/--db 로 지정한다. 비밀번호는 CLI 인자로 절대 넘기지 않고
# DB_PASSWORD 환경변수로만 전달한다 (ps 목록·쉘 히스토리 노출 방지, 08_dbms/CLAUDE.md 참고).
#
# 사용법:
#   run.sh -e mysql                              로컬 소켓/기본 접속으로 전체 항목 진단
#   run.sh -e postgres --host 127.0.0.1 --db app  원격/특정 DB 지정
#   run.sh -e mysql -i D-01,D-08                  개별(복수) 항목만 진단
#   run.sh -e mysql -g 2                          하위분류 단위(1=계정관리...4=패치관리) 진단
#   run.sh -l                                     항목 목록만 출력 (엔진 무관, 전체 26항목)
#   run.sh -o <dir>                               결과 출력 경로 지정 (기본: ../output)
#
# 엔진 미지정(-e 생략) 시 로컬에서 구동 중인 DBMS 데몬을 자동 탐지한다(단일 엔진일 때만).
# MSSQL 은 별도 run.ps1(Windows/PowerShell 5.1)을 사용한다.
# 이 스크립트는 대상 설정을 절대 변경하지 않는다 (진단 전용).

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/../lib"
GUIDE_JSON="$SCRIPT_DIR/guide.json"
CATEGORY_NUM="08"
CATEGORY_NAME="DBMS"

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
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -i) ITEM_FILTER=$2; shift 2 ;;
        -g) GROUP_FILTER=$2; shift 2 ;;
        -e) ENGINE_OVERRIDE=$2; shift 2 ;;
        -o) OUT_BASE=$2; shift 2 ;;
        -l) LIST_ONLY=1; shift ;;
        --host) DB_HOST=$2; shift 2 ;;
        --port) DB_PORT=$2; shift 2 ;;
        --user) DB_USER=$2; shift 2 ;;
        --db) DB_NAME=$2; shift 2 ;;
        --socket) DB_SOCKET=$2; shift 2 ;;
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
    DBMS_ENGINE="$ENGINE_OVERRIDE"
else
    detect_dbms_engine
    if [ -z "$DBMS_ENGINE" ]; then
        if [ -n "${DBMS_ENGINES_FOUND:-}" ]; then
            log_error "여러 DBMS 엔진이 동시에 감지되었습니다 (${DBMS_ENGINES_FOUND# }). -e 로 하나를 지정하세요."
        else
            log_error "구동 중인 DBMS 엔진을 감지하지 못했습니다. -e mysql|postgres 로 지정하세요."
        fi
        exit 2
    fi
fi

# 엔진 이름 오타(-e postgresql 등)면 preflight 를 건너뛰고 checks/<오타>/ 가 없어 전 항목 NA 가 났다(진단 검수 D-R9).
case "$DBMS_ENGINE" in
    mysql|postgres|oracle) ;;
    mssql) log_error "MSSQL 은 run.ps1(PowerShell)로 진단합니다: .\\run.ps1 -SqlHost <호스트>"; exit 2 ;;
    *) log_error "지원하지 않는 DBMS 엔진입니다: $DBMS_ENGINE (지원: mysql, postgres, oracle)"; exit 2 ;;
esac

# Oracle 은 DB_USER/DB_PASSWORD 가 모두 있어야 계정 접속을 하고, 아니면 "/ as sysdba"(로컬 OS 인증)로 접속한다.
# 예전에는 --user/--host 를 주고 DB_PASSWORD 만 빠뜨리면 조용히 로컬 sysdba 로 붙어 엉뚱한(로컬) 인스턴스를
# 진단했다(진단 검수 D-R5). 계정·원격 지정이 있는데 비밀번호가 없으면 시작 전에 멈춘다.
if [ "$DBMS_ENGINE" = "oracle" ] && [ -z "${DB_PASSWORD:-}" ] && { [ -n "${DB_USER:-}" ] || [ -n "${DB_HOST:-}" ]; }; then
    log_error "Oracle 계정 접속(--user/--host) 에는 DB_PASSWORD 환경변수가 필요합니다. 로컬 OS 인증(/ as sysdba)은 --user/--host 를 생략하세요."
    exit 2
fi

# 원격 모드(--host 가 이 호스트가 아님)면 설정 파일·프로세스 기반 항목은 MANUAL 로 돌린다(진단 검수 D-R1, db_remote_skip).
if db_is_remote; then DB_REMOTE=1; else DB_REMOTE=0; fi
export DB_REMOTE

# mktemp 가 없을 때도 예측 가능한 /tmp 고정 경로를 그대로 쓰지 않는다(root 권한으로 기존
# 심볼릭 링크를 따라가 덮어쓰는 공격 방지) - noclobber 로 새 파일만 만들고, 이미 있으면 중단.
DB_ERR_FILE=$(mktemp 2>/dev/null) || {
    DB_ERR_FILE="${TMPDIR:-/tmp}/.dbms_err.$$"
    ( umask 077; set -C; : > "$DB_ERR_FILE" ) 2>/dev/null || { log_error "임시 파일을 만들 수 없습니다: $DB_ERR_FILE"; exit 2; }
}
trap 'rm -f "$DB_ERR_FILE"' EXIT
trap 'exit 130' INT TERM

export DB_HOST DB_PORT DB_USER DB_NAME DB_SOCKET DB_ERR_FILE DBMS_ENGINE

SELECTED=""
if [ -n "$ITEM_FILTER" ]; then
    # IFS=, 를 건 채로 code_is_known 을 부르면 그 안의 $(echo $2) 가 줄바꿈으로 나뉘지 않아 모든 코드가 "알 수 없음"이
    # 됐다(Oracle 실기 중 -i 로 발견) - 콤마를 공백으로 바꿔 기본 IFS 로 돈다.
    for code in $(printf '%s' "$ITEM_FILTER" | tr ',' ' '); do if code_is_known "$code" "$ALL_CODES"; then SELECTED="$SELECTED $code"; else log_warn "알 수 없는 항목 코드라 건너뜀: $code"; fi; done
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

run_lock_acquire "$OUT_BASE" "$CATEGORY_NUM"
prepare_output_dir "$OUT_BASE" "$CATEGORY_NUM"
NDJSON="$OUT_DIR/.result.ndjson"
: > "$NDJSON"
result_trap_partial "$NDJSON" "$CATEGORY_NAME" DBMS_ENGINE
CSV_FILE="$OUT_DIR/result.csv"
csv_init "$CSV_FILE"
HOST_NAME=$(hostname 2>/dev/null || echo unknown)

echo "${C_BOLD}=== 주요정보통신기반시설 자동 진단 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
[ "$(id -u 2>/dev/null)" != "0" ] && log_warn "root 권한이 아닙니다. DB 설정 파일·프로세스 기반 항목은 읽지 못하면 ERROR 로 표시됩니다(DB 서버 호스트에서 root 실행 권장)."
echo "카테고리   : $CATEGORY_NAME"
echo "호스트     : $HOST_NAME"
echo "DBMS 엔진  : $DBMS_ENGINE"
echo "대상 항목  : ${TOTAL}개"
echo "시작 시각  : $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------------------------------------"
log_to_file "진단 시작: 엔진=$DBMS_ENGINE 대상=$TOTAL 항목"

# 접속을 항목마다 시도하기 전에 1회만 시험한다 - 실패하면 이후 DB 조회 항목은 접속 없이 ERROR
# 처리된다(lib/common.sh db_preflight). 설정 파일·프로세스 기반 항목은 그대로 진단한다.
if db_preflight; then
    echo "DB 접속    : 사전 점검 성공"
    log_to_file "DB 접속 사전 점검 성공"
    # 접속 계정 권한 확인(진단 검수 D-R2) - 부족하면 해당 항목 판정을 ERROR(CDB$ROOT 는 MANUAL)로 바꾼다.
    db_privilege_check
    if [ -n "$DB_PRIV_LIMITED" ]; then
        log_warn "$DB_PRIV_MSG - 다음 항목은 $DB_PRIV_STATUS 로 표시합니다: $DB_PRIV_LIMITED"
        log_to_file "권한 제한: $DB_PRIV_MSG ($DB_PRIV_LIMITED)"
    fi
else
    log_warn "DB 접속 사전 점검 실패 - 계정 잠금 방지를 위해 재시도하지 않고 DB 조회 항목은 ERROR 로 처리합니다: $DB_CONN_FAIL_MSG"
    log_to_file "DB 접속 사전 점검 실패(재시도 안 함): $DB_CONN_FAIL_MSG"
fi
echo "----------------------------------------------------------------------"

N_VULN=0; N_MANUAL=0; N_ERROR=0; N_NA=0; N_GOOD=0
_n=0
for code in $SELECTED; do
    _n=$((_n + 1))
    title=$(guide_field "$GUIDE_JSON" "$code" "title")
    sev=$(guide_field "$GUIDE_JSON" "$code" "severity")
    gno=$(guide_field "$GUIDE_JSON" "$code" "group_no")
    check_file="$SCRIPT_DIR/checks/$DBMS_ENGINE/$code.sh"

    CHECK_STATUS="NA"
    CHECK_DETAIL="이 항목은 $DBMS_ENGINE 대상이 아니거나 아직 구현되지 않음"
    CHECK_EVIDENCE=""

    if [ -f "$check_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="check 스크립트 오류"
        run_check_isolated "$check_file"
        db_privilege_apply "$code"
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
result_finalize "$NDJSON" "$RESULT_JSON" "$CATEGORY_NAME" "$HOST_NAME" "$DBMS_ENGINE"
rm -f "$NDJSON"
run_lock_release

render_report_html "$LIB_DIR" "$GUIDE_JSON" "$RESULT_JSON" "$OUT_DIR/report.html"
write_summary "$OUT_DIR/summary.txt" "$CATEGORY_NAME" "$HOST_NAME" "$DBMS_ENGINE" "$N_VULN" "$N_MANUAL" "$N_ERROR" "$N_NA" "$N_GOOD"

echo "----------------------------------------------------------------------"
cat "$OUT_DIR/summary.txt"
echo "----------------------------------------------------------------------"
echo "결과 경로: $OUT_DIR"
