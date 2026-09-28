#!/bin/sh
# lib/common.sh — Unix 계열(01_unix, 03_web, 08_dbms) 공용 모듈
#
# POSIX sh 로 작성 (bashism 금지, ShellCheck 통과 대상). 대상 호스트에는
# 이 파일 + 카테고리 run.sh/checks/*.sh 만 배치하면 되고, 그 외 패키지 설치는 필요 없다.
#
# 사용: 카테고리 run.sh 에서 ". ../lib/common.sh" (경로는 상대 위치에 맞게 조정)

TOOL_VERSION="0.1.0"
GUIDE_VERSION="2026"

# ---- 색상 (비TTY 이면 자동 해제) ----------------------------------------
if [ -t 1 ]; then
    C_RED='\033[31m'; C_YEL='\033[33m'; C_GRN='\033[32m'
    C_MAG='\033[35m'; C_GRY='\033[90m'; C_BOLD='\033[1m'; C_OFF='\033[0m'
else
    C_RED=''; C_YEL=''; C_GRN=''; C_MAG=''; C_GRY=''; C_BOLD=''; C_OFF=''
fi

# ---- 상태 코드 (§5) -------------------------------------------------------
# VULN(취약) > MANUAL(수동점검) > ERROR(오류) > NA(해당없음) > GOOD(양호)

status_color() {
    case "$1" in
        VULN) printf '%s' "$C_RED" ;;
        MANUAL) printf '%s' "$C_YEL" ;;
        ERROR) printf '%s' "$C_MAG" ;;
        NA) printf '%s' "$C_GRY" ;;
        GOOD) printf '%s' "$C_GRN" ;;
        *) printf '%s' "$C_OFF" ;;
    esac
}

status_label_ko() {
    case "$1" in
        VULN) echo "취약" ;;
        MANUAL) echo "수동점검" ;;
        ERROR) echo "오류" ;;
        NA) echo "해당없음" ;;
        GOOD) echo "양호" ;;
        *) echo "$1" ;;
    esac
}

# ---- 로그 -----------------------------------------------------------------
log_info()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
log_warn()  { printf '%s[%s] 경고: %s%s\n' "$C_YEL" "$(date '+%H:%M:%S')" "$*" "$C_OFF" >&2; }
log_error() { printf '%s[%s] 오류: %s%s\n' "$C_RED" "$(date '+%H:%M:%S')" "$*" "$C_OFF" >&2; }

RUN_LOG=""
log_to_file() {
    [ -n "$RUN_LOG" ] || return 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$RUN_LOG"
}

# ---- 환경(OS) 자동 감지 ----------------------------------------------------
# 결과를 OS_FAMILY 에 저장: rhel | debian | suse | solaris | aix | hpux | unknown
detect_os_family() {
    OS_FAMILY="unknown"
    case "$(uname -s 2>/dev/null)" in
        SunOS) OS_FAMILY="solaris"; return 0 ;;
        AIX) OS_FAMILY="aix"; return 0 ;;
        HP-UX) OS_FAMILY="hpux"; return 0 ;;
    esac
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}${ID_LIKE:-}" in
            *rhel*|*fedora*|*centos*|*rocky*|*almalinux*) OS_FAMILY="rhel" ;;
            *debian*|*ubuntu*) OS_FAMILY="debian" ;;
            *suse*) OS_FAMILY="suse" ;;
        esac
    fi
}

# 대화형 환경 선택 (자동 감지 실패 + TTY 인 경우)
prompt_os_family() {
    if [ ! -t 0 ]; then
        log_error "환경 자동 감지 실패. 비대화형 실행이므로 -e <env> 옵션으로 환경을 지정하세요 (rhel|debian|suse|solaris|aix|hpux)."
        exit 2
    fi
    echo "환경을 자동으로 감지하지 못했습니다. 대상 환경을 선택하세요:"
    echo "  1) rhel (RHEL/CentOS/Rocky/Alma)"
    echo "  2) debian (Debian/Ubuntu)"
    echo "  3) suse"
    echo "  4) solaris"
    echo "  5) aix"
    echo "  6) hpux"
    printf '번호 입력: '
    read -r choice
    case "$choice" in
        1) OS_FAMILY="rhel" ;;
        2) OS_FAMILY="debian" ;;
        3) OS_FAMILY="suse" ;;
        4) OS_FAMILY="solaris" ;;
        5) OS_FAMILY="aix" ;;
        6) OS_FAMILY="hpux" ;;
        *) log_error "잘못된 선택입니다."; exit 2 ;;
    esac
}

# ---- 진행 표시 --------------------------------------------------------------
# progress_show <현재순번> <전체개수> <코드> <항목명> <상태>
progress_show() {
    _cur=$1; _total=$2; _code=$3; _title=$4; _status=$5
    _pct=$(( _cur * 100 / _total ))
    _filled=$(( _pct / 5 ))
    _bar=""
    _i=0
    while [ "$_i" -lt 20 ]; do
        if [ "$_i" -lt "$_filled" ]; then _bar="${_bar}#"; else _bar="${_bar}."; fi
        _i=$((_i + 1))
    done
    _color=$(status_color "$_status")
    _label=$(status_label_ko "$_status")
    printf '[%3d/%3d] %3d%% [%s] %-8s %-40s %s%s%s\n' \
        "$_cur" "$_total" "$_pct" "$_bar" "$_code" "$_title" "$_color" "$_label" "$C_OFF"
}

banner_start() {
    _category=$1; _total=$2
    echo "${C_BOLD}=== 주요정보통신기반시설 자동 진단 (도구 v${TOOL_VERSION} / 가이드 ${GUIDE_VERSION}) ===${C_OFF}"
    echo "카테고리   : $_category"
    echo "호스트     : $(hostname 2>/dev/null || echo unknown)"
    echo "환경       : ${OS_FAMILY:-unknown}"
    echo "실행 계정  : $(id -un 2>/dev/null) (uid=$(id -u 2>/dev/null))"
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        log_warn "root 권한이 아닙니다. 일부 항목이 ERROR/MANUAL 로 표시될 수 있습니다."
    fi
    echo "대상 항목  : ${_total}개"
    echo "시작 시각  : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "----------------------------------------------------------------------"
}

# ---- 결과 수집 (JSON 조립) --------------------------------------------------
# 항목 하나의 결과를 임시 파일에 NDJSON 한 줄로 append
# result_add <outfile> <code> <status> <detail> <evidence>
json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

result_add() {
    _file=$1; _code=$2; _status=$3; _detail=$4; _evidence=$5
    printf '{"code":"%s","status":"%s","detail":"%s","evidence":"%s"}\n' \
        "$(json_escape "$_code")" "$_status" "$(json_escape "$_detail")" "$(json_escape "$_evidence")" >> "$_file"
}

# NDJSON(items) + 메타 정보를 결합해 최종 result.json 생성
# result_finalize <ndjson_file> <out_json> <category_code> <host> <env>
result_finalize() {
    _nd=$1; _out=$2; _cat=$3; _host=$4; _env=$5
    {
        printf '{\n'
        printf '  "tool_version": "%s",\n' "$TOOL_VERSION"
        printf '  "guide_version": "%s",\n' "$GUIDE_VERSION"
        printf '  "category": "%s",\n' "$_cat"
        printf '  "host": "%s",\n' "$_host"
        printf '  "env": "%s",\n' "$_env"
        printf '  "generated_at": "%s",\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
        printf '  "items": [\n'
        if [ -s "$_nd" ]; then
            _total_lines=$(wc -l < "$_nd" | tr -d ' ')
            _n=0
            while IFS= read -r line; do
                _n=$((_n + 1))
                if [ "$_n" -lt "$_total_lines" ]; then
                    printf '    %s,\n' "$line"
                else
                    printf '    %s\n' "$line"
                fi
            done < "$_nd"
        fi
        printf '  ]\n'
        printf '}\n'
    } > "$_out"
}

# ---- 보고서 생성 (Python 불필요, 파일 결합만) --------------------------------
# render_report_html <lib_dir> <guide_json> <result_json> <out_html>
render_report_html() {
    _lib=$1; _guide=$2; _result=$3; _out=$4
    cat "$_lib/report/head.html" "$_guide" "$_lib/report/mid.html" "$_result" "$_lib/report/tail.html" > "$_out"
}

# ---- guide.json 필드 조회 (자체 생성 포맷 전용, 경량 파서) --------------------
# guide.json 은 lib/extract_guide.py 가 json.dumps(indent=2) 로 생성하므로
# 문자열 값의 개행은 모두 \n 으로 이스케이프되어 각 필드가 한 줄에 위치한다.
# jq 등 외부 의존성 없이 grep/awk 만으로 top-level 필드를 조회한다.

guide_field() {
    _json=$1; _code=$2; _field=$3
    awk -v code="$_code" -v field="$_field" '
        BEGIN { incode = 0 }
        /"code":/ {
            if (index($0, "\"" code "\"") > 0) { incode = 1 } else { incode = 0 }
        }
        incode {
            pat = "\"" field "\":"
            if (index($0, pat) > 0) {
                line = $0
                sub(/^[ \t]*"[^"]+":[ \t]*/, "", line)
                sub(/,[ \t]*$/, "", line)
                gsub(/(^"|"$)/, "", line)
                print line
                exit
            }
        }
    ' "$_json"
}

guide_list_codes() {
    _json=$1
    grep -o '"code": *"[A-Z]*-[0-9]*"' "$_json" | sed -E 's/.*"([A-Z]+-[0-9]+)".*/\1/'
}

csv_escape() {
    printf '%s' "$1" | sed 's/"/""/g'
}

# ---- CSV / summary.txt -----------------------------------------------------
# csv_init <file>
csv_init() { printf 'code,severity,group,title,status,detail\n' > "$1"; }

# csv_add <file> <code> <severity> <group> <title> <status> <detail>
csv_add() {
    _f=$1
    printf '"%s","%s","%s","%s","%s","%s"\n' \
        "$(csv_escape "$2")" "$(csv_escape "$3")" "$(csv_escape "$4")" \
        "$(csv_escape "$5")" "$(csv_escape "$6")" "$(csv_escape "$7")" >> "$_f"
}

# write_summary <file> <category> <host> <env> <vuln> <manual> <error> <na> <good>
write_summary() {
    _f=$1; _cat=$2; _host=$3; _env=$4; _v=$5; _m=$6; _e=$7; _na=$8; _g=$9
    _total=$((_v + _m + _e + _na + _g))
    _base=$((_v + _g))
    _rate=0
    [ "$_base" -gt 0 ] && _rate=$((_g * 100 / _base))
    {
        echo "=== $_cat 진단 요약 ==="
        echo "호스트   : $_host"
        echo "환경     : $_env"
        echo "시각     : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "총 항목  : $_total"
        echo "----------------------------"
        printf '%-10s %5s\n' "취약"     "$_v"
        printf '%-10s %5s\n' "수동점검" "$_m"
        printf '%-10s %5s\n' "오류"     "$_e"
        printf '%-10s %5s\n' "해당없음" "$_na"
        printf '%-10s %5s\n' "양호"     "$_g"
        echo "----------------------------"
        echo "준수율(취약/양호 중): ${_rate}%"
    } > "$_f"
}

# ---- 파일 소유자/권한 공통 판정 헬퍼 -----------------------------------------
# "소유자가 X(들 중 하나)이고 권한이 N 이하" 형태의 판단기준이 반복되는 항목(U-16,18,19,20,21,22,29 등)이
# 공용으로 사용. 실행 후 CHECK_STATUS/CHECK_DETAIL/CHECK_EVIDENCE 를 채운다.
# check_owner_perm <file> <"허용 소유자 공백구분">  <최대 8진수 권한(예: 644)>
check_owner_perm() {
    _file=$1; _allowed_owners=$2; _max_perm=$3

    if [ ! -e "$_file" ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="$_file 파일이 존재하지 않음"
        CHECK_EVIDENCE=""
        return
    fi

    _owner=$(stat -c '%U' "$_file" 2>/dev/null)
    [ -z "$_owner" ] && _owner=$(stat -f '%Su' "$_file" 2>/dev/null)
    _perm=$(stat -c '%a' "$_file" 2>/dev/null)
    [ -z "$_perm" ] && _perm=$(stat -f '%OLp' "$_file" 2>/dev/null)

    _owner_ok=0
    for _o in $_allowed_owners; do
        [ "$_owner" = "$_o" ] && _owner_ok=1
    done
    _perm_ok=0
    if [ -n "$_perm" ] && [ "$_perm" -le "$_max_perm" ] 2>/dev/null; then
        _perm_ok=1
    fi

    CHECK_EVIDENCE=$(ls -l "$_file" 2>/dev/null)
    if [ "$_owner_ok" -eq 1 ] && [ "$_perm_ok" -eq 1 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="$_file 소유자(${_owner})/권한(${_perm})이 기준(허용 소유자: ${_allowed_owners} / 권한 ${_max_perm} 이하)을 충족함"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="$_file 소유자(${_owner})/권한(${_perm})이 기준(허용 소유자: ${_allowed_owners} / 권한 ${_max_perm} 이하)을 위반함"
    fi
}

# ---- "서비스 비활성화" 공통 판정 헬퍼 ----------------------------------------
# U-34/36/38/39/42/43/44/52 등 "OO 서비스가 비활성화되어 있으면 양호" 패턴 공용.
# 프로세스 실행 여부 + systemd 유닛 활성/활성화 여부로 판정한다 (inetd/xinetd 대체 서비스 포함 안 함,
# 필요 시 호출부에서 xinetd.d 설정을 추가로 확인).
# check_service_disabled <라벨> <pgrep 패턴> <"systemd 유닛 이름 공백구분(선택)">
check_service_disabled() {
    _label=$1; _proc_pattern=$2; _units=${3:-}
    _found=""

    if command -v pgrep >/dev/null 2>&1; then
        _p=$(pgrep -f "$_proc_pattern" 2>/dev/null)
        [ -n "$_p" ] && _found="$_found
프로세스 실행 중(pgrep -f '$_proc_pattern'): $_p"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        for _u in $_units; do
            systemctl is-active --quiet "$_u" 2>/dev/null && _found="$_found
systemd 유닛 활성(active): $_u"
        done
    fi

    if [ -n "$_found" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="${_label} 서비스가 활성화되어 있음"
        CHECK_EVIDENCE="$_found"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="${_label} 서비스가 비활성화되어 있음 (프로세스/systemd 유닛 미탐지)"
        CHECK_EVIDENCE=""
    fi
}

# ---- 결과 디렉토리 준비 -----------------------------------------------------
# prepare_output_dir <base_dir> <category_num>  -> OUT_DIR 에 경로 저장
prepare_output_dir() {
    _base=$1; _cat_num=$2
    _host=$(hostname 2>/dev/null || echo unknown-host)
    _ts=$(date '+%Y%m%d-%H%M%S')
    OUT_DIR="${_base}/${_host}_${_cat_num}_${_ts}"
    mkdir -p "$OUT_DIR/raw"
    RUN_LOG="$OUT_DIR/run.log"
    : > "$RUN_LOG"
}
