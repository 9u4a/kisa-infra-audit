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
ROLLBACK_DIR=""
OUT_BASE="$SCRIPT_DIR/../output"

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -r) RESULT_JSON=$2; shift 2 ;;
        -i) ITEM_FILTER=$2; shift 2 ;;
        -e) ENGINE_OVERRIDE=$2; shift 2 ;;
        -o) OUT_BASE=$2; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --yes) YES=1; shift ;;
        --rollback) ROLLBACK_DIR=$2; shift 2 ;;
        --host) DB_HOST=$2; shift 2 ;;
        --port) DB_PORT=$2; shift 2 ;;
        --user) DB_USER=$2; shift 2 ;;
        --db) DB_NAME=$2; shift 2 ;;
        --socket) DB_SOCKET=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "알 수 없는 옵션: $1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "$ENGINE_OVERRIDE" ]; then
    echo "오류: -e mysql|postgres|oracle 로 엔진을 지정해야 합니다(MSSQL은 fix.ps1 사용)." >&2
    usage
    exit 2
fi
DBMS_ENGINE="$ENGINE_OVERRIDE"

DB_ERR_FILE=$(mktemp 2>/dev/null) || {
    DB_ERR_FILE="${TMPDIR:-/tmp}/.dbms_fix_err.$$"
    ( umask 077; set -C; : > "$DB_ERR_FILE" ) 2>/dev/null || { echo "오류: 임시 파일을 만들 수 없습니다: $DB_ERR_FILE" >&2; exit 2; }
}
trap 'rm -f "$DB_ERR_FILE"; fix_lock_release' EXIT
trap 'exit 130' INT TERM
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

VULN_CODES=$(result_list_vuln_codes "$RESULT_JSON")

if [ -n "$ITEM_FILTER" ]; then
    _old_ifs=$IFS; IFS=,
    _wanted=""
    for c in $ITEM_FILTER; do _wanted="$_wanted $c"; done
    IFS=$_old_ifs
    _filtered=""
    for c in $VULN_CODES; do
        case " $_wanted " in *" $c "*) _filtered="$_filtered $c" ;; esac
    done
    VULN_CODES=$(printf '%s' "$_filtered" | sed 's/^ //')
fi

if [ -z "$VULN_CODES" ]; then
    echo "적용 대상(취약 판정) 항목이 없습니다."
    exit 0
fi

# shellcheck disable=SC2086
FIX_FILE_DIR="$SCRIPT_DIR/fixes/$DBMS_ENGINE"
[ "$APPLY" -eq 1 ] && fix_confirm_plan $VULN_CODES

fix_prepare_dir "$OUT_BASE" "$CATEGORY_NUM"
export FIX_BACKUP_DIR
TOTAL=$(echo "$VULN_CODES" | wc -w | tr -d ' ')

echo "${C_BOLD}=== 자동 조치 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
echo "카테고리   : $CATEGORY_NAME (엔진: $DBMS_ENGINE — MSSQL은 fix.ps1 사용)"
echo "모드       : $([ "$APPLY" -eq 1 ] && echo '실제 적용' || echo 'DRY-RUN (미리보기만, 아무 것도 바꾸지 않음)')"
echo "대상 항목  : ${TOTAL}개 (진단 결과 중 VULN$( [ -n "$ITEM_FILTER" ] && echo ", -i 필터 적용"))"
echo "------------------------------------------------------------------------"

N_APPLIED=0; N_SKIPPED=0; N_DECLINED=0; N_FAILED=0; N_MANUAL=0; N_PREVIEW=0; N_PARTIAL=0

for code in $VULN_CODES; do
    title=$(guide_field "$GUIDE_JSON" "$code" "title")
    grade=$(guide_field "$GUIDE_JSON" "$code" "fix")
    [ -z "$grade" ] && grade="manual"

    if [ "$grade" = "manual" ]; then
        remediation=$(guide_field "$GUIDE_JSON" "$code" "remediation")
        echo "[$code] $title"
        echo "  등급: manual (자동 조치 없음) — 가이드 조치 방법: $remediation"
        printf '%s\t%s\tMANUAL\t%s\n' "$code" "manual" "자동 조치 없음(가이드 조치 방법 안내만)" | fix_log_stamp >> "$FIX_LOG"
        N_MANUAL=$((N_MANUAL + 1))
        continue
    fi

    fix_file="$SCRIPT_DIR/fixes/$DBMS_ENGINE/$code.sh"
    check_file="$SCRIPT_DIR/checks/$DBMS_ENGINE/$code.sh"

    if [ ! -f "$fix_file" ]; then
        echo "[$code] $title"
        echo "  등급: $grade 이나 조치 스크립트 미구현(또는 $DBMS_ENGINE 대상 아님) — 건너뜀"
        printf '%s\t%s\tSKIPPED\t조치 스크립트 미구현\n' "$code" "$grade" | fix_log_stamp >> "$FIX_LOG"
        N_SKIPPED=$((N_SKIPPED + 1))
        continue
    fi

    if [ "$APPLY" -ne 1 ]; then
        echo "[$code] $title"
        echo "  등급: $grade (dry-run — 실제 적용하려면 --apply 추가)"
        _rbn=$(fix_rollback_note "$fix_file"); [ -n "$_rbn" ] && echo "  원복: $_rbn"
        N_PREVIEW=$((N_PREVIEW + 1))
        continue
    fi

    if [ "$grade" = "confirm" ]; then
        printf '[%s] %s\n  등급: confirm — 실제로 적용하시겠습니까? [y/N] ' "$code" "$title"
        _ans=""
        read -r _ans < /dev/tty 2>/dev/null || _ans=""
        case "$_ans" in
            y|Y) : ;;
            *)
                echo "  건너뜀 (사용자 미확인)"
                printf '%s\t%s\tDECLINED\t사용자가 확인하지 않음\n' "$code" "$grade" | fix_log_stamp >> "$FIX_LOG"
                N_DECLINED=$((N_DECLINED + 1))
                continue
                ;;
        esac
    fi

    FIX_CODE="$code"
    export FIX_CODE
    FIX_STATUS="ERROR"; FIX_DETAIL="조치 스크립트가 결과를 반환하지 않음"; FIX_EVIDENCE=""
    # shellcheck disable=SC1090
    . "$fix_file"
    if command -v run_fix >/dev/null 2>&1; then
        run_fix
    fi
    unset -f run_fix 2>/dev/null || true

    CHECK_STATUS="ERROR"; CHECK_DETAIL="check 스크립트 없음"; CHECK_EVIDENCE=""
    if [ -f "$check_file" ]; then
        run_check_isolated "$check_file"
    fi

    # PARTIAL/MANUAL(조치 후속 F-R6): 진단 범위 중 자동으로 바꿀 수 없는 부분(비밀번호 재설정, 다른 DB 접근까지 끊는
    # 전역·와일드카드 권한 회수 등)이 남았다는 정직한 보고다. 재검증은 VULN 으로 남는 게 정상이라 원복하지 않는다 -
    # 원복하면 이미 안전하게 적용한 부분까지 되돌린다. PARTIAL = 일부 적용(남은 부분 수동), MANUAL = 바꾼 것 없음.
    if [ "$FIX_STATUS" = "PARTIAL" ] || [ "$FIX_STATUS" = "MANUAL" ]; then
        echo "[$code] $title"
        if [ "$FIX_STATUS" = "PARTIAL" ]; then
            echo "  일부 적용 — 남은 부분은 수동 조치 필요(재검증: $CHECK_STATUS, 원복하지 않음): $FIX_DETAIL"
            _fs="PARTIAL_MANUAL"; N_PARTIAL=$((N_PARTIAL + 1))
        else
            echo "  자동 조치 불가 — 수동 조치 필요(변경 없음, 재검증: $CHECK_STATUS): $FIX_DETAIL"
            _fs="MANUAL"; N_MANUAL=$((N_MANUAL + 1))
        fi
        printf '%s\t%s\t%s\t%s (recheck=%s)\n' "$code" "$grade" "$_fs" "$FIX_DETAIL" "$CHECK_STATUS" | fix_log_stamp >> "$FIX_LOG"
    elif { [ "$FIX_STATUS" = "APPLIED" ] || [ "$FIX_STATUS" = "NA" ]; } && [ "$CHECK_STATUS" != "VULN" ] && [ "$CHECK_STATUS" != "ERROR" ]; then
        echo "[$code] $title"
        echo "  적용 완료 — 재검증 결과: $CHECK_STATUS ($FIX_DETAIL)"
        printf '%s\t%s\tAPPLIED\t%s (recheck=%s)\n' "$code" "$grade" "$FIX_DETAIL" "$CHECK_STATUS" | fix_log_stamp >> "$FIX_LOG"
        N_APPLIED=$((N_APPLIED + 1))
    else
        echo "[$code] $title"
        echo "  적용 실패 또는 재검증 실패(FIX_STATUS=$FIX_STATUS, 재검증=$CHECK_STATUS) — 원복 중"
        # 실제로 되돌리지 못한 부분이 있으면 FAILED_NOT_ROLLED_BACK 으로 정직하게 기록한다(lib/common.sh FIX_ROLLBACK_FAILS)
        FIX_ROLLBACK_FAILS=""
        fix_rollback_item "$code"
        if [ -z "$FIX_ROLLBACK_FAILS" ]; then _rbs="FAILED_ROLLED_BACK"; else _rbs="FAILED_NOT_ROLLED_BACK"; echo "  원복하지 못한 부분(수동 확인 필요):$FIX_ROLLBACK_FAILS"; fi
        printf '%s\t%s\t%s\tFIX_STATUS=%s detail=%s recheck=%s %s\n' "$code" "$grade" "$_rbs" "$FIX_STATUS" "$FIX_DETAIL" "$CHECK_STATUS" "$(printf '%s' "$FIX_ROLLBACK_FAILS" | tr '\n' ' ')" | fix_log_stamp >> "$FIX_LOG"
        N_FAILED=$((N_FAILED + 1))
    fi
    unset FIX_CODE
done

echo "------------------------------------------------------------------------"
if [ "$APPLY" -eq 1 ]; then
    echo "적용 완료: $N_APPLIED, 일부 적용(남은 부분 수동): $N_PARTIAL, 실패(원복됨): $N_FAILED, 확인거부: $N_DECLINED, 스크립트없음: $N_SKIPPED, 수동조치: $N_MANUAL"
    echo "백업 위치: $FIX_BACKUP_DIR"
    echo "원복하려면: $0 -e $DBMS_ENGINE --rollback $FIX_OUT_DIR"
else
    echo "DRY-RUN 미리보기: $N_PREVIEW 건 (--apply 로 실제 적용), 스크립트없음: $N_SKIPPED, 수동조치: $N_MANUAL"
fi
echo "로그: $FIX_LOG"
