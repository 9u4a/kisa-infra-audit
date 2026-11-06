#!/bin/sh
# lib/common.sh — Unix 계열(01_unix, 03_web, 08_dbms) 공용 모듈
#
# POSIX sh 로 작성 (bashism 금지, ShellCheck 통과 대상). 대상 호스트에는
# 이 파일 + 카테고리 run.sh/checks/*.sh 만 배치하면 되고, 그 외 패키지 설치는 필요 없다.
#
# 사용: 카테고리 run.sh 에서 ". ../lib/common.sh" (경로는 상대 위치에 맞게 조정)

# VERSION 파일이 버전의 단일 소스다. 호출부(각 카테고리
# run.sh)가 이 파일을 소싱하기 전에 반드시 LIB_DIR 을 설정해 두므로 (". $LIB_DIR/common.sh"),
# 그 값을 그대로 이용해 "$LIB_DIR/../VERSION" 을 읽는다.
if [ -n "${LIB_DIR:-}" ] && [ -f "$LIB_DIR/../VERSION" ]; then
    TOOL_VERSION=$(cat "$LIB_DIR/../VERSION")
else
    TOOL_VERSION="0.0.0-unknown"
fi
GUIDE_VERSION="2026"

# 명령 출력 파싱이 로캘에 흔들리지 않도록 C 로캘로 고정한다 - 예) 한국어 번역이 설치된 ufw 는
# "Status: active" 대신 "상태: 활성"을 출력해 U-28 이 거짓 VULN 이 됐다. 스크립트 안의 한글 문자열은
# 바이트 그대로 출력되므로 UTF-8 터미널 표시에는 영향이 없다.
LC_ALL=C
export LC_ALL

# 시스템 명령 경로를 앞에 둔다: cron 기본 PATH(/usr/bin:/bin)나 Debian 비 root 셸에서는 /usr/sbin 의
# postconf·sendmail·named·rpcinfo·sshd 를 못 찾아 "미설치 = GOOD" 이 됐다(진단 검수 R-05). 실행자의 PATH 앞쪽에
# 끼워 둔 같은 이름의 다른 프로그램이 root 로 실행되는 것도 막는다.
PATH="/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
export PATH

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

# host_name -> 결과물·잠금·대상 확인에 쓰는 호스트 이름. 최소 설치(컨테이너 이미지 등)에는 hostname 명령이 없어 "unknown" 이
# 되던 문제(실무 적용 검증 P-23) - uname -n, /proc 순으로 대신한다. 진단(run)·조치(fix)가 같은 함수를 써야 X-06 대상 확인이 맞는다.
host_name() {
    hostname 2>/dev/null || uname -n 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown
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

# Solaris/AIX/HP-UX 는 SPARC/POWER/PA-RISC 전용이라 x86 Docker 컨테이너로 실기 검증할 수 없다
# (05_network 의 "텍스트 기반 config 분석은 Docker로 검증 불가"와 같은 종류의 제약). 이 세
# 환경을 대상으로 하는 check 는 공식 문서(Oracle Solaris/IBM AIX/HPE HP-UX 매뉴얼)의 명령/경로
# 설명을 근거로 작성했을 뿐 실제 장비에서 돌려본 적이 없다는 사실을 보고서에서 숨기지 않는다 -
# 이 환경이면 CHECK_DETAIL 끝에 공통 문구를 덧붙인다. 개별 check 파일마다 호출하지 않고 각
# 카테고리 run.*/fix.* 의 디스패치 루프에서 run_check 실행 직후 한 번만 호출한다(01_unix/
# run.sh·fix.sh 참고) - 67개 파일에 똑같은 호출을 중복해 넣지 않기 위함.
# FIX_DETAIL 에 붙이려면 unverified_note (문구 자체)를 직접 이어붙일 것 - FIX_DETAIL은
# run_fix 직후 ~ run_check 재검증 전 사이, CHECK_DETAIL이 아직 이전 항목 값을 들고 있을 수
# 있는 시점에 쓰이므로 이 함수로 공유하면 엉뚱한 CHECK_DETAIL을 건드릴 위험이 있다.
unverified_note() {
    case "${OS_FAMILY:-}" in
        solaris|aix|hpux)
            printf ' [미검증: 문서 기준 구현 - Docker 등으로 실기 검증하지 못했으므로 적용 전 실제 장비에서 재확인 권장]'
            ;;
    esac
}
append_unverified_note() {
    CHECK_DETAIL="${CHECK_DETAIL}$(unverified_note)"
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
    echo "호스트     : $(host_name)"
    echo "환경       : ${OS_FAMILY:-unknown}"
    echo "실행 계정  : $(id -un 2>/dev/null) (uid=$(id -u 2>/dev/null))"
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        log_warn "root 권한이 아닙니다. 확인하지 못한 항목은 양호/해당없음 대신 ERROR 로 표시됩니다(root 실행 권장)."
    fi
    echo "대상 항목  : ${_total}개"
    echo "시작 시각  : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "----------------------------------------------------------------------"
}

# ---- 결과 수집 (JSON 조립) --------------------------------------------------
# 항목 하나의 결과를 임시 파일에 NDJSON 한 줄로 append
# result_add <outfile> <code> <status> <detail> <evidence>
# JSON 문자열은 raw TAB/CR 같은 제어문자를 이스케이프 없이 포함할 수 없다(JSON 스펙 위반).
# mysql/psql 의 배치(-B/-A) 출력은 컬럼을 TAB 으로 구분하므로, DBMS 증적(evidence)을 그대로
# 담으면 생성된 result.json 이 깨진다(Python json.loads 가 "Invalid control character" 로 거부하는
# 실제 버그를 08_dbms Docker 검증 중 발견). 이스케이프 전에 TAB/CR 을 먼저 정리한다.
# "</" 는 "<\/" 로 바꾼다(JSON 상 같은 값) - result.json 은 report.html 의 <script> 안에 그대로
# 붙으므로, 일반 사용자가 만든 파일명 등 증적에 "</script>" 가 섞이면 보고서를 연 감사자 브라우저
# 에서 HTML/JS 가 실행될 수 있다.
# TAB/CR 외의 제어문자(ESC 등 - 일반 사용자가 /tmp 에 만든 파일 이름에 넣을 수 있음)는 지운다: 남아 있으면
# result.json 이 JSON 으로 읽히지 않아 보고서가 빈 화면이 되고 merge.py 에서 그 호스트가 빠졌다(진단 검수 R-04).
json_escape() {
    printf '%s' "$1" | tr '\t\r' '  ' | tr -d '\001-\010\013\014\016-\037\177' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's#</#<\\/#g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

# perm_within <권한> <기준>  -- 8진수 권한이 기준보다 넓은 비트를 하나도 갖지 않으면 참("기준 이하").
# perm_exceeds <권한> <기준> -- 기준에 없는 비트(특수비트 포함)가 하나라도 있으면 참.
# 예전에는 [ 622 -le 640 ] 처럼 10진수로 비교해 그룹/기타 쓰기가 있는 622·0626·0444 가 "640/644/600 이하"로
# 통과했다(거짓 GOOD - 진단 전체 검수 R-03). 권한 값이 8진 숫자가 아니면 둘 다 거짓(호출부가 ERROR 처리).
perm_within() {
    case "$1" in ''|*[!0-7]*) return 1 ;; esac
    case "$2" in ''|*[!0-7]*) return 1 ;; esac
    [ $(( 0$1 & ~0$2 )) -eq 0 ]
}
perm_exceeds() {
    case "$1" in ''|*[!0-7]*) return 1 ;; esac
    case "$2" in ''|*[!0-7]*) return 1 ;; esac
    [ $(( 0$1 & ~0$2 )) -ne 0 ]
}

# code_is_known <코드> <전체 코드 목록> -- -i 로 받은 코드가 guide.json 의 항목인지. 검증 없이 "checks/<코드>.sh"
# 를 source 하면 "-i ../../x" 같은 값으로 임의 경로의 스크립트가 root 로 실행될 수 있었다(진단 검수 R-09).
code_is_known() {
    case "$1" in *[!A-Z0-9-]*|'') return 1 ;; esac
    # 호출부가 IFS=, 로 -i 값을 나누는 중에 불리므로 단어 분리(IFS)에 기대지 않는다
    printf '%s\n' "$2" | tr ' \t,' '\n\n\n' | grep -qx -- "$1"
}

# mask_secret <값>  -- 비밀번호·community 같은 값을 결과물(result.json/raw/run.log/report.html)에
# 원문으로 남기지 않도록 앞 2자와 길이만 남긴다. 예) "s3cretComm" -> "s3***(10자)"
mask_secret() {
    _ms=$1
    _ms_len=${#_ms}
    if [ "$_ms_len" -le 4 ]; then
        printf '***(%s자)' "$_ms_len"
    else
        printf '%s***(%s자)' "$(printf '%s' "$_ms" | cut -c1-2)" "$_ms_len"
    fi
}

result_add() {
    _file=$1; _code=$2; _status=$3; _detail=$4; _evidence=$5
    printf '{"code":"%s","status":"%s","detail":"%s","evidence":"%s"}\n' \
        "$(json_escape "$_code")" "$_status" "$(json_escape "$_detail")" "$(json_escape "$_evidence")" >> "$_file"
}

# result_trap_partial <ndjson> <category> <env 변수 이름> — Ctrl+C/TERM 으로 중단돼도 그때까지 진단한
# 항목을 $OUT_DIR/result.partial.json 으로 남긴다(예전에는 result.json 없이 run.log/raw 만 남았다).
# env 는 루프 도중에 정해질 수 있어(웹 엔진 감지 등) 변수 이름을 받아 중단 시점의 값을 쓴다.
result_trap_partial() {
    _RP_ND=$1; _RP_CAT=$2; _RP_ENVVAR=$3
    # HUP: SSH 세션이 끊겨도 그때까지의 결과를 남긴다(진단 검수 R-08)
    trap '_result_partial_flush; exit 130' INT TERM HUP
}
_result_partial_flush() {
    run_lock_release
    [ -s "${_RP_ND:-}" ] || return 0
    eval "_rp_env=\${$_RP_ENVVAR:-}"
    result_finalize "$_RP_ND" "$OUT_DIR/result.partial.json" "$_RP_CAT" "$(host_name)" "$_rp_env"
    log_warn "중단됨 - 지금까지 진단한 항목을 $OUT_DIR/result.partial.json 에 저장했습니다."
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
# UTF-8 BOM 을 붙인다 - 없으면 한글 Windows Excel 이 cp949 로 열어 한글이 깨진다(실무 적용 검증 P-21, Python·PowerShell
# 진입점은 이미 BOM 을 붙임)
csv_init() { printf '\357\273\277code,severity,group,title,status,detail\n' > "$1"; }

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

# ls -l 의 권한 문자열(예: "-rwxr-xr-x", 선행 파일타입 문자 포함)을 8진수로 변환한다.
# Solaris/AIX/HP-UX 는 stat(1) 자체가 없거나 GNU(-c)/BSD(-f) 와 다른 독자 플래그를 쓰는 버전이
# 섞여 있어(실기 검증 불가 환경이라 신뢰할 수 없음) 신뢰할 수 없다 - ls -l 출력은 모든 Unix
# 변형에서 수십 년간 형식이 고정되어 있어 더 안전한 공통 분모다. setuid/setgid/sticky(s/S/t/T)
# 비트는 "실행 비트가 있는지"만 반영하고 선행 특수비트 숫자(4000/2000/1000)는 생략한다 - 이
# 폴백은 이하(≤) 비교에만 쓰이므로 실제보다 작게 보이는 방향으로는 틀리지 않는다(기본 권한
# 비트 자체가 기준을 넘으면 특수비트 유무와 무관하게 이미 VULN으로 잡힌다).
_mode_str_to_octal() {
    printf '%s' "$1" | awk '{
        m = substr($0, 2, 9)
        oct = ""
        for (i = 1; i <= 9; i += 3) {
            t = substr(m, i, 3)
            v = 0
            if (substr(t,1,1) != "-") v += 4
            if (substr(t,2,1) != "-") v += 2
            if (substr(t,3,1) != "-") v += 1
            oct = oct v
        }
        print oct
    }'
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

    _owner=""; _perm=""
    # ${OS_FAMILY:-} 로 안전하게 참조해야 한다: 이 함수는 01_unix 뿐 아니라 03_web(WEB-03/13)·
    # 08_dbms(D-14/15)도 공유해서 쓰는데, 그 두 카테고리의 run.sh/fix.sh는 OS_FAMILY를 전혀
    # 설정하지 않는다(엔진 기반이라 OS 계열 개념이 없음) - set -u 환경에서 그냥 "$OS_FAMILY"로
    # 참조하면 "parameter not set" 으로 스크립트 전체가 죽는 실제 회귀 버그가 있었다(1.1.0의
    # Solaris/AIX/HP-UX 분기 추가 당시 01_unix만 생각하고 다른 카테고리의 사용처를 놓침 -
    # 03_web Docker 실기 테스트로 발견). 미설정이면 OS 계열 분기가 아닌 기본(stat 기반) 경로로
    # 간다.
    case "${OS_FAMILY:-}" in
        solaris|aix|hpux)
            # stat(1)의 존재/플래그를 신뢰할 수 없는 환경(§카테고리 고유 주의사항) - ls -l 파싱을
            # 기본으로 쓴다. -L로 심볼릭 링크를 역참조한다(아래 공통 경로와 동일한 이유).
            _lsout=$(ls -ldL "$_file" 2>/dev/null)
            if [ -n "$_lsout" ]; then
                _owner=$(printf '%s' "$_lsout" | awk '{print $3}')
                _perm=$(_mode_str_to_octal "$(printf '%s' "$_lsout" | awk '{print $1}')")
            fi
            ;;
        *)
            # -L(심볼릭 링크 역참조)을 반드시 써야 한다: 링크 자체의 권한 비트는 커널이 전혀
            # 사용하지 않고(항상 777 처럼 보임) 실제 접근 제어는 가리키는 대상 파일의 소유자/
            # 권한으로 결정된다. Oracle Free 23ai+ 가 listener.ora/sqlnet.ora 를 oradata/
            # dbconfig/ 의 실제 파일에 대한 심볼릭 링크로 배치하는 것처럼 설정 파일이 링크인
            # 경우가 실제로 있다 - -L 없이 stat 하면 링크의 겉보기 777을 그대로 읽어 실제로는
            # 안전한 644 대상 파일도 거짓 VULN으로 오판한다(D-14/D-15 Oracle Docker 실기 테스트로 발견).
            _owner=$(stat -L -c '%U' "$_file" 2>/dev/null)
            [ -z "$_owner" ] && _owner=$(stat -L -f '%Su' "$_file" 2>/dev/null)
            _perm=$(stat -L -c '%a' "$_file" 2>/dev/null)
            [ -z "$_perm" ] && _perm=$(stat -L -f '%OLp' "$_file" 2>/dev/null)
            ;;
    esac

    # 소유자/권한을 끝내 알아내지 못한 경우 VULN으로 단정하지 않는다 - "확인 못 함"과
    # "위반함"은 다르다(ERROR로 정직하게 보고해야 거짓 VULN을 피할 수 있다).
    if [ -z "$_owner" ] || [ -z "$_perm" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$_file 의 소유자/권한을 확인하지 못함 (stat/ls 명령 실패 또는 미지원)"
        CHECK_EVIDENCE=""
        return
    fi

    _owner_ok=0
    for _o in $_allowed_owners; do
        [ "$_owner" = "$_o" ] && _owner_ok=1
    done
    _perm_ok=0
    if perm_within "$_perm" "$_max_perm"; then
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

# proc_match_pids <ERE> -- U-C1(1.4.0): 실행 파일 이름(argv[0] 의 basename, 커널 스레드 "[nfsd]" 는 괄호를 뗀 이름,
# "sshd: user" 처럼 이름을 바꾼 프로세스는 ":" 앞)이 ERE 에 맞는 프로세스의 PID(한 줄에 하나). 명령줄 전체를 보는
# pgrep -f/pkill -f 는 데몬 이름이 인자에 들어간 편집기·로그 조회·셸 명령까지 잡아(진단은 거짓 VULN, 조치는 엉뚱한
# 프로세스 종료) 쓰지 않는다. ERE 는 awk 의 -v 대신 환경변수로 넘긴다(-v 는 "\." 같은 이스케이프를 미리 풀어 버림).
proc_match_pids() {
    ps -e -o pid= -o args= 2>/dev/null | PM_RE="$1" PM_SELF="$$" awk '
        $1 != ENVIRON["PM_SELF"] {
            a = $2; sub(/^\[/, "", a); sub(/\]$/, "", a); sub(/:$/, "", a)
            n = split(a, p, "/"); if (p[n] ~ ENVIRON["PM_RE"]) print $1
        }'
}

# fix_kill_procs <ERE> -- 조치용: proc_match_pids 와 같은 기준(실행 파일 이름)으로 찾은 프로세스만 종료한다.
# 예전 조치의 pkill -f 는 명령줄에 서비스 이름이 든 다른 프로세스(설정 파일을 연 편집기 등)까지 종료했다(U-C1).
fix_kill_procs() {
    for _fkp in $(proc_match_pids "$1"); do
        kill "$_fkp" 2>/dev/null
    done
    return 0
}

# ---- "서비스 비활성화" 공통 판정 헬퍼 ----------------------------------------
# U-34/36/38/39/42/43/44/52 등 "OO 서비스가 비활성화되어 있으면 양호" 패턴 공용.
# 프로세스 실행 여부 + systemd 유닛 활성/활성화 여부로 판정한다 (inetd/xinetd 대체 서비스 포함 안 함,
# 필요 시 호출부에서 xinetd.d 설정을 추가로 확인).
# check_service_disabled <라벨> <pgrep 패턴> <"systemd 유닛 이름 공백구분(선택)">
check_service_disabled() {
    _label=$1; _proc_pattern=$2; _units=${3:-}
    _found=""
    _detect_ok=0

    # U-C1(1.4.0): 프로세스는 "실행 파일 이름"(argv[0] 의 basename)으로만 찾는다(proc_match_pids). 예전 pgrep -f 는 명령줄
    # 전체를 봐서, 데몬이 없어도 "vi /etc/snmp/snmpd.conf"·"tail -f ...snmpd.log" 같은 다른 프로세스 때문에 VULN 이었다.
    # ps 가 없으면 pgrep(프로세스 이름 기준, -f 없음)으로 폴백하고, 둘 다 없으면 "활성 아님"으로 단정하지 않고
    # ERROR 로 정직하게 보고한다(아래 참고).
    if command -v ps >/dev/null 2>&1; then
        _detect_ok=1
        _p=$(proc_match_pids "$_proc_pattern" | tr '\n' ' ')
        [ -n "$_p" ] && _found="$_found
프로세스 실행 중(실행 파일 이름 ~ '$_proc_pattern'): $_p"
    elif command -v pgrep >/dev/null 2>&1; then
        _detect_ok=1
        _p=$(pgrep "$_proc_pattern" 2>/dev/null | tr '\n' ' ')
        [ -n "$_p" ] && _found="$_found
프로세스 실행 중(pgrep '$_proc_pattern'): $_p"
    fi

    _sd_timeout=""
    if command -v systemctl >/dev/null 2>&1; then
        for _u in $_units; do
            _sd_rc=0
            run_to 10 systemctl is-active --quiet "$_u" 2>/dev/null || _sd_rc=$?
            if [ "$_sd_rc" -eq 0 ]; then
                _found="$_found
systemd 유닛 활성(active): $_u"
                continue
            fi
            # systemctl 이 응답하지 않으면(시간 초과) "비활성"으로 보지 않는다(S6 - 예전에는 GOOD 이었다)
            case "$_sd_rc" in 124|137) _sd_timeout="$_sd_timeout $_u"; continue ;; esac
            # 지금 꺼져 있어도 enabled 면 재부팅 시(소켓 유닛은 첫 연결 시) 기동된다 - 예전에는 is-active 만 봐서
            # GOOD 이었다(진단 검수 U-R16).
            _en=$( { run_to 10 systemctl is-enabled "$_u" 2>/dev/null; echo "__rc=$?"; } | sed -n '1p;$p')
            case "$_en" in *__rc=124|*__rc=137) _sd_timeout="$_sd_timeout $_u"; continue ;; esac
            _en=$(printf '%s\n' "$_en" | sed -n '1p')
            case "$_en" in
                enabled|enabled-runtime|indirect) _found="$_found
systemd 유닛 활성화(is-enabled=$_en, 재부팅/연결 시 기동): $_u" ;;
            esac
        done
    fi

    # inetd 로 기동되는 서비스는 연결 전에는 프로세스가 없다 - /etc/inetd.conf 의 주석이 아닌 줄(첫 필드=서비스명)을
    # 본다(진단 검수 U-R6). inetd 는 같은 서비스가 여러 줄이면 각각 등록하므로 하나라도 있으면 활성으로 본다.
    _inetd_svcs=${4:-}
    if [ -n "$_inetd_svcs" ] && [ -f /etc/inetd.conf ]; then
        if [ -r /etc/inetd.conf ]; then
            _il=$(awk -v s=" $_inetd_svcs " '$0 !~ /^[[:space:]]*#/ && NF >= 6 && index(s, " " $1 " ") { print }' /etc/inetd.conf 2>/dev/null)
            [ -n "$_il" ] && _found="$_found
/etc/inetd.conf 활성 항목:
$_il"
        else
            _inetd_unread=1
        fi
    fi

    # pgrep/ps 둘 다 없으면 프로세스 상태를 전혀 확인할 수 없다 - "비활성화됨(양호)"으로
    # 단정하면 거짓 양호가 된다(check_owner_perm의 stat 실패 사례와 같은 종류의 문제).
    # 활성 근거를 하나라도 찾았으면 나머지를 확인하지 못했어도 VULN 이다.
    if [ -n "$_found" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="${_label} 서비스가 활성화되어 있음"
        CHECK_EVIDENCE="$_found"
    elif [ "$_detect_ok" -eq 0 ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="${_label} 서비스 실행 여부를 확인할 ps/pgrep 명령을 찾지 못함"
        CHECK_EVIDENCE=""
    elif [ -n "$_sd_timeout" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="${_label}: systemctl 이 응답하지 않아(시간 초과) 유닛 상태를 확인하지 못함:$_sd_timeout"
        CHECK_EVIDENCE=""
    elif [ "${_inetd_unread:-0}" -eq 1 ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="${_label}: /etc/inetd.conf 를 읽을 수 없어 inetd 기동 여부를 확인하지 못함"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="${_label} 서비스가 비활성화되어 있음 (프로세스/systemd 유닛(active·enabled)/inetd.conf 미탐지)"
        CHECK_EVIDENCE=""
    fi
}

# ---- 01_unix 전용 헬퍼 (check_service_disabled 와 같은 영역) ----------------------------
# scan_find <최대 건수> <find 조건...> -- 파일시스템 전수 검색(U-15/23/25). 예전에는 find / -xdev 로 루트
# 파일시스템만 보고 별도 파일시스템(/home, /var 등)은 detail 에만 적은 채 GOOD 이었고, 시간 제한·실패 확인도
# 없었다(진단 검수 U-R10). 이제 / 와 별도 "로컬" 파일시스템을 각각 -xdev 로 검색하고(원격·자동마운트는 마운트
# 연쇄·멈춤 위험으로 제외 - scan_remote_mounts 로 detail 에 남긴다), SCAN_TIMEOUT(기본 900초) 제한을 건다.
# 출력: 찾은 경로(최대 건수) + 끝까지 돌았으면 마지막 줄 "__RC=<find 종료코드>"(124=시간 초과).
# 최대 건수를 넘으면 그 자리에서 끊는다(이때는 __RC 줄이 없음 - 결과가 있으므로 판정에는 지장 없음).
scan_local_mounts() {
    printf '/\n'
    [ -r /proc/mounts ] || return 0
    awk '$2 != "/" && $3 !~ /^(proc|sysfs|devtmpfs|devpts|tmpfs|cgroup2?|mqueue|securityfs|pstore|bpf|tracefs|debugfs|configfs|fusectl|hugetlbfs|autofs|binfmt_misc|overlay|nsfs|rpc_pipefs|efivarfs|ramfs|squashfs|nfsd|selinuxfs|nfs4?|cifs|smb3|smbfs|fuse|fuse\..*|sshfs|glusterfs|ceph|9p|davfs|afs)$/ \
        && $2 !~ /^\/(proc|sys|dev|run)(\/|$)/ && $2 !~ /^\/etc\/(hosts|hostname|resolv\.conf)$/ && $2 !~ /\\/ { print $2 }' /proc/mounts | sort -u
}
scan_remote_mounts() {
    [ -r /proc/mounts ] || return 0
    awk '$3 ~ /^(nfs4?|cifs|smb3|smbfs|fuse|fuse\..*|sshfs|glusterfs|ceph|9p|davfs|afs)$/ { printf "%s(%s) ", $2, $3 }' /proc/mounts
}
scan_find() {
    _sf_lim=$1; shift
    _sf_starts=$(scan_local_mounts)
    low_prio true >/dev/null 2>&1   # LOW_PRIO_PREFIX 초기화 - run_to(timeout)는 셸 함수 low_prio 를 실행할 수 없다
    _sf_ifs=$IFS; IFS='
'
    # shellcheck disable=SC2086
    set -f; set -- $_sf_starts -xdev "$@"; set +f
    IFS=$_sf_ifs
    # shellcheck disable=SC2086
    { run_to "${SCAN_TIMEOUT:-900}" $LOW_PRIO_PREFIX find "$@" 2>/dev/null; echo "__RC=$?"; } \
        | awk -v n="$_sf_lim" '/^__RC=/ { print; exit } { c++; if (c <= n) print; else exit }'
}
# fix_inetd_disable <서비스명...> -- /etc/inetd.conf 에서 해당 서비스의 주석이 아닌 줄을 주석 처리한다(조치 전용).
# check_service_disabled 가 inetd.conf 를 보게 되면서(진단 검수 U-R6) 조치도 같은 기준을 따라야 재검증이 통과한다.
# 바꾼 것이 있으면 inetd 를 reload 하고 0, 없으면 1.
fix_inetd_disable() {
    [ -f /etc/inetd.conf ] || return 1
    _fid_s=" $* "
    awk -v s="$_fid_s" '$0 !~ /^[[:space:]]*#/ && NF >= 6 && index(s, " " $1 " ") { f = 1 } END { exit !f }' /etc/inetd.conf || return 1
    fix_backup /etc/inetd.conf
    _fid_tmp="/etc/inetd.conf.kisa.$$"
    awk -v s="$_fid_s" '$0 !~ /^[[:space:]]*#/ && NF >= 6 && index(s, " " $1 " ") { print "#" $0; next } { print }' /etc/inetd.conf > "$_fid_tmp" \
        && cat "$_fid_tmp" > /etc/inetd.conf
    rm -f "$_fid_tmp"
    if command -v systemctl >/dev/null 2>&1; then
        for _fid_u in inetd openbsd-inetd inetutils-inetd; do
            run_to 30 systemctl try-reload-or-restart "$_fid_u" 2>/dev/null
        done
    elif [ -f /var/run/inetd.pid ]; then
        kill -HUP "$(cat /var/run/inetd.pid)" 2>/dev/null
    fi
    return 0
}

# banner_custom_lines <파일> -- 배포판 기본 문구를 뺀 나머지 줄 수(U-62 진단·조치 공용). 진단 검수 U-R17: 예전에는
# 비어 있지만 않으면 경고 메시지로 인정해, 설치 직후의 /etc/issue("Debian GNU/Linux 12 \n \l", "\S / Kernel \r on
# an \m")·/etc/motd(Debian 무보증 안내문)만으로 GOOD 이었다. getty 이스케이프(\n \l \S \r \m 등)만 남는 줄, 배포판
# 이름이 든 줄, 알려진 기본 안내 문구 줄은 경고문으로 세지 않는다(문구 판별은 휴리스틱).
banner_custom_lines() {
    awk '{ l = $0; gsub(/\\[a-zA-Z]/, "", l); gsub(/[[:space:]]/, "", l) }
        l == "" { next }
        /Kernel .* on an/ || /GNU\/Linux/ || /Debian|Ubuntu|Red Hat|CentOS|Rocky|AlmaLinux|Fedora|SUSE/ { next }
        /programs included with the|exact distribution terms|individual files in \/usr\/share\/doc|ABSOLUTELY NO WARRANTY|permitted by applicable law/ { next }
        /^[[:space:]]*\*[[:space:]]+(Documentation|Management|Support):/ { next }
        { c++ } END { print c + 0 }' "$1" 2>/dev/null
}

# snmpd_conf_lines <주 설정 파일> -- snmpd.conf 의 주석·빈 줄을 뺀 설정 줄을 includeFile/includeDir(*.conf) 까지 따라가
# 출력한다(U-59~61). 읽지 못한 파일은 "!unread<TAB>경로" 줄로 알린다. com2sec(6) 의 "-Cn <context>" 옵션은 지워
# 필드 위치(secname source community)를 고정한다. 예전에는 주 파일 한 개만 봐서 Debian 기본 "includeDir
# /etc/snmp/snmpd.conf.d" 아래 설정과 rocommunity6 등 IPv6 지시어를 놓쳤다(진단 검수 U-R15).
snmpd_conf_lines() {
    awk -v main="$1" '
    function rd(f, d,   line, rc, a, k, n, i, cmd, lst, m) {
        if (d > 5 || (f in seen)) return
        seen[f] = 1
        while ((rc = (getline line < f)) > 0) {
            if (line ~ /^[[:space:]]*(#|$)/) continue
            n = split(line, a, /[ \t]+/); k = (a[1] == "" ? 2 : 1)
            if (tolower(a[k]) == "includefile") { inc[++ni] = a[k + 1]; incd[ni] = d + 1; continue }
            if (tolower(a[k]) == "includedir") {
                cmd = "ls -1 \"" a[k + 1] "\" 2>/dev/null"; m = 0
                while ((cmd | getline lst) > 0) if (lst ~ /\.conf$/) { inc[++ni] = a[k + 1] "/" lst; incd[ni] = d + 1 }
                close(cmd); continue
            }
            if (tolower(a[k]) ~ /^com2sec6?$/ && a[k + 1] == "-Cn") { sub(/[[:space:]]-Cn[[:space:]]+[^[:space:]]+/, "", line) }
            print line
        }
        close(f)
        if (rc < 0) print "!unread\t" f
    }
    BEGIN { ni = 0; rd(main, 0); for (j = 1; j <= ni; j++) rd(inc[j], incd[j]) }'
}

# snmpd_conf_files <주 설정 파일> -- snmpd_conf_lines 와 같은 규칙(includeFile/includeDir *.conf, 깊이 5, 중복 제외)으로
# 따라간 설정 파일 경로를 한 줄에 하나씩 출력한다(조치 U-59~61 용 - 진단이 보는 파일을 조치도 똑같이 고치도록).
# 읽지 못한 파일은 "!unread<TAB>경로" 줄로 알린다(F-R8).
snmpd_conf_files() {
    awk -v main="$1" '
    function rd(f, d,   line, rc, a, k, cmd, lst) {
        if (d > 5 || (f in seen)) return
        seen[f] = 1
        while ((rc = (getline line < f)) > 0) {
            if (line ~ /^[[:space:]]*(#|$)/) continue
            split(line, a, /[ \t]+/); k = (a[1] == "" ? 2 : 1)
            if (tolower(a[k]) == "includefile") { inc[++ni] = a[k + 1]; incd[ni] = d + 1; continue }
            if (tolower(a[k]) == "includedir") {
                cmd = "ls -1 \"" a[k + 1] "\" 2>/dev/null"
                while ((cmd | getline lst) > 0) if (lst ~ /\.conf$/) { inc[++ni] = a[k + 1] "/" lst; incd[ni] = d + 1 }
                close(cmd)
            }
        }
        close(f)
        if (rc < 0) print "!unread\t" f; else print f
    }
    BEGIN { ni = 0; rd(main, 0); for (j = 1; j <= ni; j++) rd(inc[j], incd[j]) }'
}

# named_conf_flatten <주 설정 파일> -- BIND 설정을 include 까지 따라가 주석(// # /* */)을 지우고 문장 단위로 펼친다.
# 출력(탭 구분): "@file<TAB>경로"(읽은 파일) / "!unread<TAB>경로"(읽지 못한 include) /
#               "<문맥><TAB><키워드><TAB><값>" - 문맥은 options, zone "x", view "v" > zone "x" 처럼 블록 경로
#               (존 이름에 "/" 가 들어갈 수 있어 구분자는 " > ").
#               키워드는 allow-transfer·allow-update·update-policy(값=중괄호 안 내용), type(zone 종류).
# Debian 의 /etc/bind/named.conf 는 include 만 있고, 여러 줄 블록·주석도 흔하다 - 예전에는 첫 grep 한 줄만 봐서
# 주석 속 값이나 include 안의 설정을 못 봤다(진단 검수 U-R5). 상대 경로 include 는 주 설정 파일의 폴더 기준.
named_conf_flatten() {
    awk -v main="$1" '
    function strip(t,   o, a, b) {
        o = ""
        while ((a = index(t, "/*")) > 0) {
            b = index(substr(t, a + 2), "*/")
            o = o substr(t, 1, a - 1) " "
            if (b == 0) { t = ""; break }
            t = substr(t, a + 2 + b + 1)
        }
        t = o t
        gsub(/\/\/[^\n]*/, "", t); gsub(/#[^\n]*/, "", t)
        return t
    }
    function slurp(f, depth,   line, txt, rc, out, stmt, p) {
        if (depth > 10 || (f in seen)) return ""
        seen[f] = 1
        txt = ""
        while ((rc = (getline line < f)) > 0) txt = txt line "\n"
        close(f)
        if (rc < 0) { print "!unread\t" f; return "" }
        print "@file\t" f
        txt = strip(txt); out = ""
        while (match(txt, /include[ \t\n]+"[^"]+"[ \t\n]*;/)) {
            stmt = substr(txt, RSTART, RLENGTH)
            p = stmt; sub(/^include[ \t\n]+"/, "", p); sub(/".*$/, "", p)
            if (p !~ /^\//) p = base "/" p
            out = out substr(txt, 1, RSTART - 1) " " slurp(p, depth + 1) " "
            txt = substr(txt, RSTART + RLENGTH)
        }
        return out txt
    }
    BEGIN {
        base = main; sub(/\/[^\/]*$/, "", base); if (base == "") base = "/"
        t = slurp(main, 0)
        gsub(/[{};]/, " & ", t)
        n = split(t, tok, /[ \t\n]+/)
        sp = 0; nst = 0; cap = 0
        for (i = 1; i <= n; i++) {
            w = tok[i]; if (w == "") continue
            if (cap > 0) {
                if (w == "{") cap++
                else if (w == "}") { cap--; if (cap == 0) { print ctx() "\t" capkey "\t" capval; skipsemi = 1; continue } }
                capval = capval " " w
                continue
            }
            if (w == "{") {
                k = tolower(st[1])
                if (k == "allow-transfer" || k == "allow-update" || k == "update-policy") { cap = 1; capkey = k; capval = "" }
                else { h = st[1]; for (j = 2; j <= nst; j++) if (tolower(st[j]) != "in") h = h " " st[j]; stack[++sp] = h }
                nst = 0; continue
            }
            if (w == "}") { if (sp > 0) sp--; nst = 0; skipsemi = 1; continue }
            if (w == ";") {
                if (!skipsemi && nst >= 2 && tolower(st[1]) == "type") print ctx() "\ttype\t" tolower(st[2])
                nst = 0; skipsemi = 0; continue
            }
            skipsemi = 0
            st[++nst] = w
        }
    }
    function ctx(   c, j) { c = ""; for (j = 1; j <= sp; j++) c = c (j > 1 ? " > " : "") stack[j]; return (c == "" ? "-" : c) }
    '
}

# ---- /proc 기반 프로세스 조회 (pgrep/ps 미설치 환경 대비) ---------------------
# 최소 구성 컨테이너 이미지(예: 공식 httpd/nginx Docker 이미지)는 procps 패키지가 없어
# ps/pgrep 자체가 없는 경우가 흔하다. /proc/*/comm, /proc/*/status 는 커널이 직접 제공하므로
# 항상 사용 가능하며, 이 방식이 더 이식성이 높다 (03_web WEB-09 구현 중 실제로 겪은 문제).
# proc_pids_by_comm <comm 이름> -> 일치하는 PID 목록(줄바꿈 구분)
# 프로세스마다 cat 을 fork 하던 것을 셸 내장 read 로 바꿨다(프로세스가 많은 운영 서버 부하 - S4, WEB-R12).
proc_pids_by_comm() {
    _name=$1
    for _p in /proc/[0-9]*; do
        _c=""
        { IFS= read -r _c < "$_p/comm"; } 2>/dev/null || [ -n "$_c" ] || continue
        [ "$_c" = "$_name" ] && echo "${_p#/proc/}"
    done
}

# proc_uid <pid> -> 실제 UID (숫자, root=0)
proc_uid() {
    { while read -r _pu_k _pu_v _pu_rest; do
        [ "$_pu_k" = "Uid:" ] && { echo "$_pu_v"; break; }
    done < "/proc/$1/status"; } 2>/dev/null
}

# proc_pids_by_comm_glob <패턴> -> 부분 일치(예: "*pmon*")하는 PID 목록. Oracle 백그라운드
# 프로세스(ora_pmon_<SID> 등)처럼 이름에 인스턴스 SID가 섞여 정확 일치를 쓸 수 없는 경우 사용.
proc_pids_by_comm_glob() {
    _pattern=$1
    for _p in /proc/[0-9]*; do
        [ -r "$_p/comm" ] || continue
        _c=$(cat "$_p/comm" 2>/dev/null)
        case "$_c" in $_pattern) echo "${_p#/proc/}" ;; esac
    done
}

# ---- 진단 대기·부하 제한 (운영 안전 기준 S2·S4, 1.2.3) ----------------------------------
# run_to <초> <명령...> — timeout 명령이 있으면 제한 시간을 건다(없으면 그대로 실행, 대상 무설치 원칙).
# 종료코드 124 = 시간 초과. rpcinfo(portmapper DROP), sendmail -bt(DNS 대기), firewall-cmd/hostnamectl
# (D-Bus 장애) 처럼 운영 환경에서 멈출 수 있는 명령에 쓴다.
run_to() {
    _rt_s=$1; shift
    # -k 5: TERM 을 무시하는 명령도 5초 뒤 KILL(진단 검수 R-07). -k 가 없는 구형 timeout 은 그대로 쓴다.
    if [ -z "${_RUN_TO_K+x}" ]; then
        _RUN_TO_K=""; timeout -k 1 1 true >/dev/null 2>&1 && _RUN_TO_K="-k 5"
    fi
    # 진단(run) 중 한 번 시간 초과한 명령은 같은 실행 안에서 다시 기다리지 않고 바로 124 를 돌려준다(S2).
    # D-Bus 장애로 systemctl 이 멈추면 서비스 항목마다 10초씩 수십 번 기다려 진단이 수십 분 걸렸다(run_safety 의
    # HANG_CMDS 검사로 확인). 표시는 출력 폴더($OUT_DIR, 항목 서브셸도 공유)의 .run_to_timeout/<명령 이름> - 조치(fix)는
    # OUT_DIR 이 없어 적용되지 않는다. nice/ionice 접두(전수 검색 find)는 명령마다 범위가 달라 기억하지 않는다.
    _rt_mark=""
    case "${1:-}" in
        nice|ionice|*/nice|*/ionice|"") : ;;
        *) [ -n "${OUT_DIR:-}" ] && [ -d "$OUT_DIR" ] && _rt_mark="$OUT_DIR/.run_to_timeout/$(basename "$1")" ;;
    esac
    [ -n "$_rt_mark" ] && [ -e "$_rt_mark" ] && return 124
    _rt_rc=0
    # shellcheck disable=SC2086
    if command -v timeout >/dev/null 2>&1; then timeout $_RUN_TO_K "$_rt_s" "$@" || _rt_rc=$?; else "$@" || _rt_rc=$?; fi
    if { [ "$_rt_rc" -eq 124 ] || [ "$_rt_rc" -eq 137 ]; } && [ -n "$_rt_mark" ]; then
        mkdir -p "$OUT_DIR/.run_to_timeout" 2>/dev/null && : > "$_rt_mark" 2>/dev/null
    fi
    return "$_rt_rc"
}

# low_prio <명령...> — 가능하면 nice -n 19 + ionice -c3(idle) 로 실행해 운영 서비스의 CPU/디스크 I/O 와
# 경쟁하지 않게 한다(find / 전수 검색용). 컨테이너 등에서 ionice 가 거부되면 그 단계만 빼고 실행한다 -
# 접두 명령이 실패해 본 명령이 아예 안 돌면 "검색 결과 없음 = 양호" 로 오인되므로 미리 시험해 본다.
low_prio() {
    if [ -z "${_LOW_PRIO_INIT:-}" ]; then
        _LOW_PRIO_INIT=1; LOW_PRIO_PREFIX=""
        nice -n 19 true >/dev/null 2>&1 && LOW_PRIO_PREFIX="nice -n 19"
        # -c3(idle) 는 디스크 I/O 가 끊이지 않는 서버에서 사실상 무기한 대기할 수 있다(진단 검수 R-07) - 최하위 best-effort
        ionice -c2 -n7 true >/dev/null 2>&1 && LOW_PRIO_PREFIX="$LOW_PRIO_PREFIX ionice -c2 -n7"
    fi
    # shellcheck disable=SC2086
    $LOW_PRIO_PREFIX "$@"
}

# path_fs_type <경로> — /proc/mounts 에서 경로를 포함하는 가장 긴 마운트 지점의 파일시스템 종류.
# 경로 자체는 stat 하지 않는다(automount 를 깨우거나 응답 없는 NFS 에서 멈추지 않게).
path_fs_type() {
    [ -r /proc/mounts ] || return 0
    awk -v p="$1" '{ m = $2; if (p == m || m == "/" || index(p, m "/") == 1) { if (length(m) > bl) { bl = length(m); t = $3 } } }
        END { print t }' /proc/mounts
}

# is_remote_or_auto_fs <경로> — 원격(NFS/CIFS 등)·자동마운트(autofs)·FUSE 위의 경로면 0. 홈 디렉터리를
# 계정 수만큼 순회하는 check 가 이런 경로를 건드리면 마운트가 연쇄로 일어나거나 stale 마운트에서 멈춘다.
is_remote_or_auto_fs() {
    case "$(path_fs_type "$1")" in
        nfs|nfs4|cifs|smb3|smbfs|autofs|fuse|fuse.*|sshfs|glusterfs|ceph|9p|davfs|afs) return 0 ;;
    esac
    return 1
}

# scan_excluded_mounts — find / -xdev 가 검색하지 않는 별도 실제 파일시스템(/home, /var 등) 목록.
# 결과가 "없음=양호"일 때 검색 범위가 루트 파일시스템뿐이었다는 사실을 판정 근거에 남기기 위함.
scan_excluded_mounts() {
    [ -r /proc/mounts ] || return 0
    awk '$2 != "/" && $3 !~ /^(proc|sysfs|devtmpfs|devpts|tmpfs|cgroup2?|mqueue|securityfs|pstore|bpf|tracefs|debugfs|configfs|fusectl|hugetlbfs|autofs|binfmt_misc|overlay|nsfs|rpc_pipefs|efivarfs|ramfs|squashfs|nfsd|selinuxfs)$/ \
        && $2 !~ /^\/(proc|sys|dev|run)(\/|$)/ && $2 !~ /^\/etc\/(hosts|hostname|resolv\.conf)$/ { printf "%s(%s) ", $2, $3 }' /proc/mounts
}

# ---- 결과 디렉토리 준비 -----------------------------------------------------
# make_private_dir <dir>  -- 실행자만 접근 가능한(700) 디렉터리 생성. 진단 증적(계정 목록·설정 발췌)과
# 조치 백업(/etc/shadow 사본 등)이 같은 서버의 다른 사용자에게 읽히지 않게 한다. umask 를 전역으로
# 바꾸지 않는 이유: fix 스크립트가 새로 만드는 대상 설정 파일까지 600 이 되어 서비스가 못 읽을 수 있음.
make_private_dir() {
    ( umask 077; mkdir -p "$1" ) && chmod 700 "$1"
}

# prepare_output_dir <base_dir> <category_num>  -> OUT_DIR 에 경로 저장
prepare_output_dir() {
    _base=$1; _cat_num=$2
    _host=$(host_name)
    _ts=$(date '+%Y%m%d-%H%M%S')
    # 같은 초에 두 번 실행해도 결과가 섞이지 않도록 PID 를 붙인다('-' 구분이라 merge.py 규칙과 호환)
    OUT_DIR="${_base}/${_host}_${_cat_num}_${_ts}-$$"
    make_private_dir "$OUT_DIR"
    make_private_dir "$OUT_DIR/raw"
    # 진단(run.*) 전용 함수라 여기서는 umask 를 바꿔도 된다(진단은 출력물 외에 파일을 만들지 않음). 폴더만 700 이고
    # 안의 result.json·raw/*.txt 는 644 로 만들어져, 결과 폴더를 복사·압축해 옮기면 그대로 남에게 읽혔다
    # (진단 실행 검수 lib/tests/run_safety.sh 로 발견).
    umask 077
    RUN_LOG="$OUT_DIR/run.log"
    : > "$RUN_LOG"
}

# nonroot_unverified -- root 가 아닌 실행에서 GOOD/NA 를 "확인 못 함(ERROR)"으로 바꾼다(01_unix·03_web 진입점 공용).
# 읽지 못한 설정 파일(vsftpd.conf 0600, named.conf 0640, tomcat conf 등)·보이지 않는 남의 프로세스(hidepid)를
# 각 check 가 "설정 없음/서비스 없음"으로 받아들여 GOOD·NA 가 나왔다(진단 검수 U-R1/WEB-R3). check 마다
# [ -r ] 를 빠짐없이 넣는 대신 진입점에서 일괄 처리한다 - 원래 판정은 detail 에 남긴다. VULN 은 그대로 둔다.
nonroot_unverified() {
    [ "$(id -u 2>/dev/null)" = "0" ] && return 0
    case "$CHECK_STATUS" in
        GOOD|NA)
            CHECK_DETAIL="root 권한이 아니어서 확인하지 못함(읽을 수 없는 설정·프로세스를 '없음'으로 판정했을 수 있음) - root 로 다시 실행 필요 / 비 root 판정: $CHECK_STATUS - $CHECK_DETAIL"
            CHECK_STATUS="ERROR" ;;
    esac
}

# run_lock_acquire <out_base> <category_num> / run_lock_release -- 같은 카테고리 진단이 동시에 두 번 돌지 않게 한다
# (전체 find / 가 겹쳐 운영 서버 부하가 두 배가 됨 - 진단 검수 R-06). 잠금은 결과 기본 폴더 안에 두고,
# 잠금을 잡은 프로세스가 이미 없으면(강제 종료 등) 정리하고 진행한다.
run_lock_acquire() {
    ( umask 077; mkdir -p "$1" ) 2>/dev/null
    RUN_LOCK_DIR="$1/.run_$2.lock"
    if ! mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
        _lpid=$(cat "$RUN_LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$_lpid" ] && kill -0 "$_lpid" 2>/dev/null; then
            log_error "같은 카테고리 진단이 이미 실행 중입니다(PID $_lpid). 끝난 뒤 다시 실행하세요. (잠금: $RUN_LOCK_DIR)"
            RUN_LOCK_DIR=""
            exit 2
        fi
        log_warn "이전 진단이 남긴 잠금을 정리합니다(PID ${_lpid:-알 수 없음}, 실행 중 아님)."
        rm -rf "$RUN_LOCK_DIR"
        mkdir "$RUN_LOCK_DIR" 2>/dev/null || { log_error "잠금을 만들 수 없습니다: $RUN_LOCK_DIR"; RUN_LOCK_DIR=""; exit 2; }
    fi
    echo $$ > "$RUN_LOCK_DIR/pid"
}
run_lock_release() {
    [ -n "${RUN_LOCK_DIR:-}" ] && rm -rf "$RUN_LOCK_DIR"
    RUN_LOCK_DIR=""
}

# run_check_isolated <check 파일>  -- check 1개를 서브셸에서 실행하고 CHECK_STATUS/DETAIL/EVIDENCE 를 받아온다.
# 예전에는 check 를 진단 셸에서 바로 실행해, 한 항목의 미설정 변수 하나(set -u)로 진단 전체가 중간에 죽었다
# (U-61: snmpd.conf 의 "rocommunity <값>" 처럼 인자가 적은 줄 - 진단 실행 검수로 발견). 이제 그 항목만 ERROR
# 로 남기고 다음 항목으로 넘어간다. 조치(fix.sh)의 재검증에도 쓴다 - 재검증이 죽으면 원복으로 이어져야 한다.
run_check_isolated() {
    _rci_dir="${OUT_DIR:-${FIX_OUT_DIR:-${TMPDIR:-/tmp}}}/.check.$$"
    rm -rf "$_rci_dir"
    ( umask 077; mkdir -p "$_rci_dir" ) || { CHECK_STATUS="ERROR"; CHECK_DETAIL="임시 폴더를 만들 수 없음: $_rci_dir"; CHECK_EVIDENCE=""; return; }
    (
        CHECK_STATUS="ERROR"; CHECK_DETAIL="check 가 결과를 남기지 않음"; CHECK_EVIDENCE=""
        # shellcheck disable=SC1090
        . "$1"
        if command -v run_check >/dev/null 2>&1; then run_check; fi
        printf '%s' "$CHECK_STATUS" > "$_rci_dir/s"
        printf '%s' "$CHECK_DETAIL" > "$_rci_dir/d"
        printf '%s' "$CHECK_EVIDENCE" > "$_rci_dir/e"
    ) 2> "$_rci_dir/err"
    _rci_rc=$?
    if [ -f "$_rci_dir/s" ] && [ -f "$_rci_dir/e" ]; then
        CHECK_STATUS=$(cat "$_rci_dir/s"); CHECK_DETAIL=$(cat "$_rci_dir/d"); CHECK_EVIDENCE=$(cat "$_rci_dir/e")
    else
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="check 실행 중 비정상 종료(rc=$_rci_rc): $(tail -n 2 "$_rci_dir/err" 2>/dev/null | tr '\n' ' ')"
        CHECK_EVIDENCE=""
    fi
    [ -s "$_rci_dir/err" ] && cat "$_rci_dir/err" >&2
    rm -rf "$_rci_dir"
}

# ---- 진단 진입점 공통 흐름 (1.5.0 D2) ---------------------------------------------------------------
# 01_unix·03_web·08_dbms run.sh 가 똑같이 복붙하던 목록 출력·대상 선정·출력 준비·항목 루프·마무리를 한 곳에 둔다.
# 진입점은 옵션 해석·환경(엔진) 감지·배너처럼 카테고리마다 다른 부분만 남기고, 아래 순서로 부른다:
#   run_list_items(-l) → run_select_codes → run_begin_output → (배너) → run_items → run_finish
# 진입점이 정해 두어야 하는 전역: GUIDE_JSON, LIB_DIR, OUT_BASE, CATEGORY_NUM, CATEGORY_NAME, ITEM_FILTER, GROUP_FILTER.

# run_list_items -- -l: 항목 목록만 출력
run_list_items() {
    printf '%-8s %-4s %-8s %s\n' "코드" "중요도" "분류" "항목명"
    for _rl_code in $(guide_list_codes "$GUIDE_JSON"); do
        printf '%-8s %-4s %-8s %s\n' "$_rl_code" "$(guide_field "$GUIDE_JSON" "$_rl_code" severity)" \
            "$(guide_field "$GUIDE_JSON" "$_rl_code" group_no)" "$(guide_field "$GUIDE_JSON" "$_rl_code" title)"
    done
}

# run_select_codes -- -i/-g 로 SELECTED·TOTAL 을 정한다. 대상이 없으면 exit 2.
# -i 는 콤마를 공백으로 바꿔 기본 IFS 로 나눈다(IFS=, 를 건 채 code_is_known 을 부르면 모든 코드가 "알 수 없음"이 됐다).
run_select_codes() {
    ALL_CODES=$(guide_list_codes "$GUIDE_JSON")
    SELECTED=""
    if [ -n "$ITEM_FILTER" ]; then
        for _rs_code in $(printf '%s' "$ITEM_FILTER" | tr ',' ' '); do
            if code_is_known "$_rs_code" "$ALL_CODES"; then SELECTED="$SELECTED $_rs_code"; else log_warn "알 수 없는 항목 코드라 건너뜀: $_rs_code"; fi
        done
    elif [ -n "$GROUP_FILTER" ]; then
        for _rs_code in $ALL_CODES; do
            [ "$(guide_field "$GUIDE_JSON" "$_rs_code" group_no)" = "$GROUP_FILTER" ] && SELECTED="$SELECTED $_rs_code"
        done
    else
        SELECTED="$ALL_CODES"
    fi
    TOTAL=$(echo "$SELECTED" | wc -w | tr -d ' ')
    if [ "$TOTAL" -eq 0 ]; then
        log_error "대상 항목이 없습니다."
        exit 2
    fi
}

# run_begin_output <환경 변수 이름> -- 잠금·출력 폴더·NDJSON(중단 시 부분 결과 보존)·CSV 를 준비한다.
# 인자는 result_trap_partial 이 중단 시점에 읽을 환경 변수 "이름"이다(OS_FAMILY / WEB_ENGINES / DBMS_ENGINE).
run_begin_output() {
    run_lock_acquire "$OUT_BASE" "$CATEGORY_NUM"
    prepare_output_dir "$OUT_BASE" "$CATEGORY_NUM"
    NDJSON="$OUT_DIR/.result.ndjson"
    : > "$NDJSON"
    result_trap_partial "$NDJSON" "$CATEGORY_NAME" "$1"
    CSV_FILE="$OUT_DIR/result.csv"
    csv_init "$CSV_FILE"
    HOST_NAME=$(host_name)
}

# run_items <check 폴더> <파일 없을 때 상태> <파일 없을 때 detail> [후처리 함수]
#   SELECTED 의 항목마다 <check 폴더>/<코드>.sh 를 run_check_isolated 로 실행하고, 후처리 함수(<코드> 인자, 예:
#   nonroot_unverified·append_unverified_note·db_privilege_apply 묶음)를 부른 뒤 결과를 기록한다. 후처리 함수는
#   RUN_CHECK_FILE 로 check 파일 경로를 볼 수 있다. N_VULN..N_GOOD 를 센다.
run_items() {
    _ri_dir=$1; _ri_mstatus=$2; _ri_mdetail=$3; _ri_hook=${4:-}
    N_VULN=0; N_MANUAL=0; N_ERROR=0; N_NA=0; N_GOOD=0
    _ri_n=0
    for _ri_code in $SELECTED; do
        _ri_n=$((_ri_n + 1))
        _ri_title=$(guide_field "$GUIDE_JSON" "$_ri_code" "title")
        _ri_sev=$(guide_field "$GUIDE_JSON" "$_ri_code" "severity")
        _ri_gno=$(guide_field "$GUIDE_JSON" "$_ri_code" "group_no")
        RUN_CHECK_FILE="$_ri_dir/$_ri_code.sh"

        CHECK_STATUS=$_ri_mstatus
        CHECK_DETAIL=$_ri_mdetail
        CHECK_EVIDENCE=""
        if [ -f "$RUN_CHECK_FILE" ]; then
            run_check_isolated "$RUN_CHECK_FILE"
        fi
        if [ -n "$_ri_hook" ]; then "$_ri_hook" "$_ri_code"; fi

        progress_show "$_ri_n" "$TOTAL" "$_ri_code" "$_ri_title" "$CHECK_STATUS"
        log_to_file "$_ri_code [$CHECK_STATUS] $CHECK_DETAIL"
        result_add "$NDJSON" "$_ri_code" "$CHECK_STATUS" "$CHECK_DETAIL" "$CHECK_EVIDENCE"
        csv_add "$CSV_FILE" "$_ri_code" "$_ri_sev" "$_ri_gno" "$_ri_title" "$CHECK_STATUS" "$CHECK_DETAIL"
        if [ -n "$CHECK_EVIDENCE" ]; then
            printf '%s\n' "$CHECK_EVIDENCE" > "$OUT_DIR/raw/$_ri_code.txt"
        fi

        case "$CHECK_STATUS" in
            VULN) N_VULN=$((N_VULN + 1)) ;;
            MANUAL) N_MANUAL=$((N_MANUAL + 1)) ;;
            ERROR) N_ERROR=$((N_ERROR + 1)) ;;
            NA) N_NA=$((N_NA + 1)) ;;
            GOOD) N_GOOD=$((N_GOOD + 1)) ;;
        esac
    done
}

# run_finish <환경 표기> -- result.json·report.html·summary.txt 를 만들고 잠금을 푼 뒤 요약을 출력한다.
run_finish() {
    RESULT_JSON="$OUT_DIR/result.json"
    result_finalize "$NDJSON" "$RESULT_JSON" "$CATEGORY_NAME" "$HOST_NAME" "$1"
    rm -f "$NDJSON"
    run_lock_release

    render_report_html "$LIB_DIR" "$GUIDE_JSON" "$RESULT_JSON" "$OUT_DIR/report.html"
    write_summary "$OUT_DIR/summary.txt" "$CATEGORY_NAME" "$HOST_NAME" "$1" "$N_VULN" "$N_MANUAL" "$N_ERROR" "$N_NA" "$N_GOOD"

    echo "----------------------------------------------------------------------"
    cat "$OUT_DIR/summary.txt"
    echo "----------------------------------------------------------------------"
    echo "결과 경로: $OUT_DIR"
    echo "  - result.json / result.csv  (기계 판독·표계산용)"
    echo "  - report.html                (브라우저로 열람)"
    echo "  - summary.txt / run.log      (요약 · 실행 로그)"
}

# ---- 분할 모듈 로드 (1.5.0 D3) ----------------------------------------------------------------------
# 웹·DBMS·조치 헬퍼는 같은 폴더의 common_web.sh / common_db.sh / common_fix.sh 에 있다. 대상 호스트에는 lib/ 폴더를
# 통째로 둔다. 호출부는 LIB_DIR 을 정한 뒤 이 파일을 source 하고, 테스트 일부는 저장소 루트에서 ". lib/common.sh" 로 부른다.
_kisa_lib=${LIB_DIR:-lib}
for _kisa_part in common_web.sh common_db.sh common_fix.sh; do
    if [ ! -f "$_kisa_lib/$_kisa_part" ]; then
        echo "오류: $_kisa_lib/$_kisa_part 가 없음 - lib/ 폴더를 통째로 배치할 것" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    . "$_kisa_lib/$_kisa_part"
done
unset _kisa_part
