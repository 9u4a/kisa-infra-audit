# 03_web/fix.sh — Web 서비스 자동 조치 진입점 (POSIX sh, Apache/Nginx/Tomcat 대상)
#
# run.sh(진단)와 완전히 분리된 진입점이다. run.sh 는 대상 설정을 절대 바꾸지 않지만, 이
# 스크립트는 실제로 시스템을 변경한다 — 항상 dry-run(기본값)으로 먼저 확인하고, 적용 전
# 자동 백업, 적용 직후 재검증(VULN/ERROR 이탈 확인), 실패 시 자동 원복을 수행한다
# (01_unix/fix.sh 와 완전히 동일한 흐름).
#
# IIS 대상은 별도 03_web/fix.ps1(PowerShell)을 사용한다.
#
# 사용법:
#   fix.sh -r <result.json>                       dry-run: 적용 대상·등급만 출력
#   fix.sh -r <result.json> -i WEB-01,WEB-16 --apply  지정 항목만 실제 적용
#   fix.sh -r <result.json> --apply --yes         적용 전 변경 목록 확인(1회)을 생략(confirm 등급은 항상 개별 y/N)
#   fix.sh --rollback <output/host_03_fix_TS 디렉터리>   백업에서 원복
#
# guide.json 의 fix 등급: auto(영향 없음, 즉시 적용) / confirm(서비스 영향 가능, 항목별 확인
# 필수) / manual(정책 판단 필요 또는 안전한 값을 스크립트가 결정할 수 없어 자동 조치 없음).

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/../lib"
GUIDE_JSON="$SCRIPT_DIR/guide.json"
CATEGORY_NUM="03"
CATEGORY_NAME="Web"

# shellcheck disable=SC1090
. "$LIB_DIR/common.sh"

RESULT_JSON=""
ITEM_FILTER=""
APPLY=0
YES=0
ROLLBACK_DIR=""
OUT_BASE="$SCRIPT_DIR/../output"

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -r) RESULT_JSON=$2; shift 2 ;;
        -i) ITEM_FILTER=$2; shift 2 ;;
        -o) OUT_BASE=$2; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --yes) YES=1; shift ;;
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
[ "$APPLY" -eq 1 ] && fix_confirm_plan $VULN_CODES

fix_prepare_dir "$OUT_BASE" "$CATEGORY_NUM"
export FIX_BACKUP_DIR
TOTAL=$(echo "$VULN_CODES" | wc -w | tr -d ' ')

echo "${C_BOLD}=== 자동 조치 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
echo "카테고리   : $CATEGORY_NAME (Apache/Nginx/Tomcat — IIS는 fix.ps1 사용)"
echo "모드       : $([ "$APPLY" -eq 1 ] && echo '실제 적용' || echo 'DRY-RUN (미리보기만, 아무 것도 바꾸지 않음)')"
echo "대상 항목  : ${TOTAL}개 (진단 결과 중 VULN$( [ -n "$ITEM_FILTER" ] && echo ", -i 필터 적용"))"
echo "------------------------------------------------------------------------"

N_APPLIED=0; N_SKIPPED=0; N_DECLINED=0; N_FAILED=0; N_MANUAL=0; N_PREVIEW=0

# 설정 문법 검사 기준선(운영 안전 기준 F2): 적용 전에 통과하던 엔진만 항목마다 다시 검사해, 조치가
# 설정을 깨뜨렸으면(다음 reload/재시작 때 서비스가 안 뜨는 상태) 그 항목을 즉시 원복한다. 원래부터
# 검사에 실패하던 설정은 조치 탓으로 오인하지 않도록 기준선에서 제외하고 경고만 한다.
WEB_BASE_OK=""
if [ "$APPLY" -eq 1 ]; then
    detect_web_engines
    for _e in apache nginx; do
        case " $WEB_ENGINES " in *" $_e "*)
            web_config_test "$_e"
            case $? in
                0) WEB_BASE_OK="$WEB_BASE_OK $_e" ;;
                1) log_warn "$_e 설정이 조치 전부터 문법 검사에 실패합니다 - 이 엔진은 적용 후 문법 검증을 할 수 없습니다: $(printf '%s' "$WEB_CONFIG_TEST_OUT" | tail -n 2 | tr '\n' ' ')" ;;
                *) log_warn "$_e 설정 문법 검사 도구(apachectl/httpd/nginx)를 찾지 못해 적용 후 문법 검증을 할 수 없습니다." ;;
            esac
        esac
    done
fi

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

    fix_file="$SCRIPT_DIR/fixes/$code.sh"
    check_file="$SCRIPT_DIR/checks/$code.sh"

    if [ ! -f "$fix_file" ]; then
        echo "[$code] $title"
        echo "  등급: $grade 이나 조치 스크립트 미구현 — 건너뜀"
        printf '%s\t%s\tSKIPPED\t조치 스크립트 미구현\n' "$code" "$grade" | fix_log_stamp >> "$FIX_LOG"
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

    if [ "$FIX_STATUS" = "APPLIED" ]; then
        for _e in $WEB_BASE_OK; do
            if ! web_config_test "$_e"; then
                FIX_STATUS="ERROR"
                FIX_DETAIL="$FIX_DETAIL / 적용 후 $_e 설정 문법 검사 실패(그대로 두면 다음 재시작 때 서비스 기동 실패) - 원복: $(printf '%s' "$WEB_CONFIG_TEST_OUT" | tail -n 3 | tr '\n' ' ')"
                break
            fi
        done
    fi

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
    echo "적용 완료: $N_APPLIED, 실패(원복됨): $N_FAILED, 확인거부: $N_DECLINED, 스크립트없음: $N_SKIPPED, 수동조치: $N_MANUAL"
    echo "백업 위치: $FIX_BACKUP_DIR"
    echo "원복하려면: $0 --rollback $FIX_OUT_DIR"
else
    echo "DRY-RUN 미리보기: $N_PREVIEW 건 (--apply 로 실제 적용), 스크립트없음: $N_SKIPPED, 수동조치: $N_MANUAL"
fi
echo "로그: $FIX_LOG"
