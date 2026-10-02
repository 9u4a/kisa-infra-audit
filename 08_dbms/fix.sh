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
#   fix.sh -e mysql -r <result.json> --apply --yes          auto 등급 전체 적용(confirm 은 항상 개별 y/N)
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

DB_ERR_FILE=$(mktemp 2>/dev/null || echo "/tmp/.dbms_fix_err.$$")
trap 'rm -f "$DB_ERR_FILE"' EXIT
export DB_HOST DB_PORT DB_USER DB_NAME DB_SOCKET DB_ERR_FILE DBMS_ENGINE

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

fix_prepare_dir "$OUT_BASE" "$CATEGORY_NUM"
export FIX_BACKUP_DIR
TOTAL=$(echo "$VULN_CODES" | wc -w | tr -d ' ')

echo "${C_BOLD}=== 자동 조치 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
echo "카테고리   : $CATEGORY_NAME (엔진: $DBMS_ENGINE — MSSQL은 fix.ps1 사용)"
echo "모드       : $([ "$APPLY" -eq 1 ] && echo '실제 적용' || echo 'DRY-RUN (미리보기만, 아무 것도 바꾸지 않음)')"
echo "대상 항목  : ${TOTAL}개 (진단 결과 중 VULN$( [ -n "$ITEM_FILTER" ] && echo ", -i 필터 적용"))"
echo "------------------------------------------------------------------------"

N_APPLIED=0; N_SKIPPED=0; N_DECLINED=0; N_FAILED=0; N_MANUAL=0; N_PREVIEW=0

for code in $VULN_CODES; do
    title=$(guide_field "$GUIDE_JSON" "$code" "title")
    grade=$(guide_field "$GUIDE_JSON" "$code" "fix")
    [ -z "$grade" ] && grade="manual"

    if [ "$grade" = "manual" ]; then
        remediation=$(guide_field "$GUIDE_JSON" "$code" "remediation")
        echo "[$code] $title"
        echo "  등급: manual (자동 조치 없음) — 가이드 조치 방법: $remediation"
        printf '%s\t%s\tMANUAL\t%s\n' "$code" "manual" "자동 조치 없음(가이드 조치 방법 안내만)" >> "$FIX_LOG"
        N_MANUAL=$((N_MANUAL + 1))
        continue
    fi

    fix_file="$SCRIPT_DIR/fixes/$DBMS_ENGINE/$code.sh"
    check_file="$SCRIPT_DIR/checks/$DBMS_ENGINE/$code.sh"

    if [ ! -f "$fix_file" ]; then
        echo "[$code] $title"
        echo "  등급: $grade 이나 조치 스크립트 미구현(또는 $DBMS_ENGINE 대상 아님) — 건너뜀"
        printf '%s\t%s\tSKIPPED\t조치 스크립트 미구현\n' "$code" "$grade" >> "$FIX_LOG"
        N_SKIPPED=$((N_SKIPPED + 1))
        continue
    fi

    if [ "$APPLY" -ne 1 ]; then
        echo "[$code] $title"
        echo "  등급: $grade (dry-run — 실제 적용하려면 --apply 추가)"
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
                printf '%s\t%s\tDECLINED\t사용자가 확인하지 않음\n' "$code" "$grade" >> "$FIX_LOG"
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
        # shellcheck disable=SC1090
        . "$check_file"
        if command -v run_check >/dev/null 2>&1; then
            run_check
        fi
        unset -f run_check 2>/dev/null || true
    fi

    if { [ "$FIX_STATUS" = "APPLIED" ] || [ "$FIX_STATUS" = "NA" ]; } && [ "$CHECK_STATUS" != "VULN" ] && [ "$CHECK_STATUS" != "ERROR" ]; then
        echo "[$code] $title"
        echo "  적용 완료 — 재검증 결과: $CHECK_STATUS ($FIX_DETAIL)"
        printf '%s\t%s\tAPPLIED\t%s (recheck=%s)\n' "$code" "$grade" "$FIX_DETAIL" "$CHECK_STATUS" >> "$FIX_LOG"
        N_APPLIED=$((N_APPLIED + 1))
    else
        echo "[$code] $title"
        echo "  적용 실패 또는 재검증 실패(FIX_STATUS=$FIX_STATUS, 재검증=$CHECK_STATUS) — 원복 중"
        fix_rollback_item "$code"
        printf '%s\t%s\tFAILED_ROLLED_BACK\tFIX_STATUS=%s detail=%s recheck=%s\n' "$code" "$grade" "$FIX_STATUS" "$FIX_DETAIL" "$CHECK_STATUS" >> "$FIX_LOG"
        N_FAILED=$((N_FAILED + 1))
    fi
    unset FIX_CODE
done

echo "------------------------------------------------------------------------"
if [ "$APPLY" -eq 1 ]; then
    echo "적용 완료: $N_APPLIED, 실패(원복됨): $N_FAILED, 확인거부: $N_DECLINED, 스크립트없음: $N_SKIPPED, 수동조치: $N_MANUAL"
    echo "백업 위치: $FIX_BACKUP_DIR"
    echo "원복하려면: $0 -e $DBMS_ENGINE --rollback $FIX_OUT_DIR"
else
    echo "DRY-RUN 미리보기: $N_PREVIEW 건 (--apply 로 실제 적용), 스크립트없음: $N_SKIPPED, 수동조치: $N_MANUAL"
fi
echo "로그: $FIX_LOG"
