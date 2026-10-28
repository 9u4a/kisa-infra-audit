#!/bin/sh
# lib/common.sh — Unix 계열(01_unix, 03_web, 08_dbms) 공용 모듈
#
# POSIX sh 로 작성 (bashism 금지, ShellCheck 통과 대상). 대상 호스트에는
# 이 파일 + 카테고리 run.sh/checks/*.sh 만 배치하면 되고, 그 외 패키지 설치는 필요 없다.
#
# 사용: 카테고리 run.sh 에서 ". ../lib/common.sh" (경로는 상대 위치에 맞게 조정)

# VERSION 파일이 버전의 단일 소스다 (루트 CLAUDE.md 버전 규칙 참고). 호출부(각 카테고리
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
    echo "호스트     : $(hostname 2>/dev/null || echo unknown)"
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
    result_finalize "$_RP_ND" "$OUT_DIR/result.partial.json" "$_RP_CAT" "$(hostname 2>/dev/null || echo unknown)" "$_rp_env"
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

# ---- "서비스 비활성화" 공통 판정 헬퍼 ----------------------------------------
# U-34/36/38/39/42/43/44/52 등 "OO 서비스가 비활성화되어 있으면 양호" 패턴 공용.
# 프로세스 실행 여부 + systemd 유닛 활성/활성화 여부로 판정한다 (inetd/xinetd 대체 서비스 포함 안 함,
# 필요 시 호출부에서 xinetd.d 설정을 추가로 확인).
# check_service_disabled <라벨> <pgrep 패턴> <"systemd 유닛 이름 공백구분(선택)">
check_service_disabled() {
    _label=$1; _proc_pattern=$2; _units=${3:-}
    _found=""
    _detect_ok=0

    # pgrep 은 원래 Solaris 유래 명령이라(이후 Linux/BSD로 역포팅됨) Solaris/AIX/HP-UX 에도
    # 보통 존재한다 - 있으면 그대로 쓴다. 혹시 없는 극히 드문 환경을 위해 ps -ef | grep -E
    # 로 폴백한다(둘 다 없으면 "활성 아님"으로 단정하지 않고 ERROR로 정직하게 보고 - 아래 참고).
    if command -v pgrep >/dev/null 2>&1; then
        _detect_ok=1
        _p=$(pgrep -f "$_proc_pattern" 2>/dev/null)
        [ -n "$_p" ] && _found="$_found
프로세스 실행 중(pgrep -f '$_proc_pattern'): $_p"
    elif command -v ps >/dev/null 2>&1; then
        _detect_ok=1
        _p=$(ps -ef 2>/dev/null | grep -E "$_proc_pattern" | grep -v grep)
        [ -n "$_p" ] && _found="$_found
프로세스 실행 중(ps -ef | grep -E '$_proc_pattern'): $_p"
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

# ---- 웹 엔진 자동 탐지 및 설정 경로 조회 (03_web 전용) -------------------------
# 여러 엔진이 동시에 설치되어 있을 수 있으므로 공백 구분 목록으로 반환한다.
# WEB_ENGINES 가 이미 정해져 있으면(run.sh -e 로 지정했거나 진입점이 이미 탐지함) 다시 탐지하지 않는다 -
# 예전에는 각 check 가 이 함수를 다시 불러 -e 지정이 무시됐다(진단 검수 WEB-R5).
# pgrep 이 없는 최소 이미지에서도 동작하도록 실행 중 프로세스는 /proc 로 확인한다.
detect_web_engines() {
    [ -n "${WEB_ENGINES:-}" ] && return 0
    WEB_ENGINES=""
    { command -v httpd >/dev/null 2>&1 || command -v apache2 >/dev/null 2>&1 || \
      [ -x /usr/local/apache2/bin/httpd ] || [ -n "$(proc_pids_by_comm httpd)$(proc_pids_by_comm apache2)" ]; } && \
      WEB_ENGINES="$WEB_ENGINES apache"
    { command -v nginx >/dev/null 2>&1 || [ -x /usr/local/nginx/sbin/nginx ] || [ -n "$(proc_pids_by_comm nginx)" ]; } && \
      WEB_ENGINES="$WEB_ENGINES nginx"
    { [ -n "${CATALINA_HOME:-}" ] || [ -n "${CATALINA_BASE:-}" ] || [ -n "$(tomcat_pids)" ] || \
      [ -x /usr/local/tomcat/bin/catalina.sh ] || tomcat_conf_dir >/dev/null 2>&1; } && WEB_ENGINES="$WEB_ENGINES tomcat"
    pgrep -f jeus >/dev/null 2>&1 && WEB_ENGINES="$WEB_ENGINES jeus"
    pgrep -x wsbtoc >/dev/null 2>&1 && WEB_ENGINES="$WEB_ENGINES webtob"
    WEB_ENGINES=$(printf '%s' "$WEB_ENGINES" | sed -E 's/^ //')
}

# apache_conf_path — 대표적인 설치 레이아웃(공식 도커/소스, Debian/Ubuntu, RHEL 계열) 순으로 탐색
apache_conf_path() {
    for p in /usr/local/apache2/conf/httpd.conf /etc/apache2/apache2.conf /etc/httpd/conf/httpd.conf /usr/local/apache/conf/httpd.conf; do
        [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

# apache_extra_confs — httpd.conf 가 "실제로" Include/IncludeOptional 하는 파일만 찾아 반환한다
# (메인 설정 제외). 공식 Docker 이미지 등은 conf/extra/ 안에 기본적으로 비활성(주석 처리된
# Include) 샘플 설정이 다수 들어있어, 디렉터리를 통째로 훑으면 실제로는 로드되지 않는 설정
# (예: httpd-dav.conf 의 "Dav On" 예시)을 활성 설정으로 오판하는 실제 버그가 있었다
# (03_web WEB-18 을 Docker 컨테이너로 검증하다 발견). 반드시 Include 체인을 따라간다.
# 1.3.x(진단 검수 WEB-R1/R6): Debian/Ubuntu 는 ServerRoot 가 주석이라 예전 계산(메인 설정의 상위의 상위)이
# /etc 가 되어 mods-enabled·sites-enabled·conf-enabled 를 하나도 따라가지 못했다(WEB-04/18 등 거짓 GOOD).
# 이제 ServerRoot 미지정 시 메인 설정 폴더(conf/ 안이면 그 상위)를 기준으로 하고, 소문자 include·디렉터리
# Include(안의 모든 파일)·Include 순환(같은 파일은 한 번만, 깊이 16·파일 512개 상한 - S2)을 처리한다.
_WEB_NL='
'
# _web_expand_pattern <절대경로 패턴> -> 일치하는 파일(디렉터리면 그 안의 모든 파일, 정렬) 목록
_web_expand_pattern() {
    for _wep in $1; do
        if [ -d "$_wep" ]; then
            find "$_wep" -maxdepth 8 -type f 2>/dev/null | LC_ALL=C sort
        elif [ -f "$_wep" ]; then
            printf '%s\n' "$_wep"
        fi
    done
}

# apache_server_root <메인 설정> -> ServerRoot(주석이 아닌 지시자), 없으면 메인 설정 폴더(conf/ 안이면 그 상위)
apache_server_root() {
    _asr=$(awk 'tolower($1) == "serverroot" { v = $2; gsub(/"/, "", v); print v; exit }' "$1" 2>/dev/null)
    if [ -z "$_asr" ]; then
        _asr=$(dirname "$1")
        [ "$(basename "$_asr")" = conf ] && _asr=$(dirname "$_asr")
    fi
    printf '%s\n' "$_asr"
}

# _apache_walk <메인 설정> <ServerRoot> -> "파일<TAB>줄번호<TAB>내용" 을 Apache 가 읽는 순서대로(Include 자리에서
# 포함 파일을 펼쳐) 출력한다. 파일마다 "파일<TAB>0<TAB>" 표지를 먼저 낸다(빈 파일·읽지 못한 파일도 목록에 남게).
# 상한에 걸려 펼치지 못한 Include 가 있으면 "!trunc<TAB>0<TAB>" 을 낸다(web_conf_files 가 확인 불가로 처리).
# 재귀 함수 대신 스택(줄바꿈 구분 "깊이|시작줄|파일")을 쓴다 - POSIX sh 에는 지역 변수가 없다.
_apache_walk() {
    _aw_root=$2; _aw_stack="0|1|$1"; _aw_seen="$1"; _aw_loads=0
    while [ -n "$_aw_stack" ]; do
        _aw_top=${_aw_stack%%"$_WEB_NL"*}
        case "$_aw_stack" in *"$_WEB_NL"*) _aw_stack=${_aw_stack#*"$_WEB_NL"} ;; *) _aw_stack="" ;; esac
        _aw_depth=${_aw_top%%|*}; _aw_rest=${_aw_top#*|}
        _aw_start=${_aw_rest%%|*}; _aw_file=${_aw_rest#*|}
        [ "$_aw_start" = 1 ] && printf '%s\t0\t\n' "$_aw_file"
        _aw_out=$(awk -v s="$_aw_start" -v f="$_aw_file" '
            NR < s { next }
            { line = $0; sub(/\r$/, "", line); printf "%s\t%d\t%s\n", f, NR, line
              t = line; sub(/^[ \t]+/, "", t)
              if (tolower(t) ~ /^include(optional)?[ \t]/) {
                  p = t; sub(/^[^ \t]+[ \t]+/, "", p); sub(/[ \t]+$/, "", p); gsub(/"/, "", p)
                  printf "@INC@%d|%s\n", NR, p; exit
              } }' "$_aw_file" 2>/dev/null)
        _aw_inc=""
        case "$_aw_out" in
            *"$_WEB_NL@INC@"*) _aw_inc=${_aw_out##*"$_WEB_NL@INC@"}; _aw_out=${_aw_out%"$_WEB_NL@INC@"*} ;;
        esac
        [ -n "$_aw_out" ] && printf '%s\n' "$_aw_out"
        [ -n "$_aw_inc" ] || continue
        _aw_next="$_aw_depth|$((${_aw_inc%%|*} + 1))|$_aw_file"
        _aw_pat=${_aw_inc#*|}
        _aw_kids=""
        if [ "$_aw_depth" -ge 16 ] || [ "$_aw_loads" -ge 512 ]; then
            printf '!trunc\t0\t\n'
        else
            case "$_aw_pat" in /*) ;; *) _aw_pat="$_aw_root/$_aw_pat" ;; esac
            while IFS= read -r _aw_c; do
                [ -n "$_aw_c" ] || continue
                case "$_WEB_NL$_aw_seen$_WEB_NL" in *"$_WEB_NL$_aw_c$_WEB_NL"*) continue ;; esac
                _aw_seen="$_aw_seen$_WEB_NL$_aw_c"; _aw_loads=$((_aw_loads + 1))
                _aw_kids="$_aw_kids$((_aw_depth + 1))|1|$_aw_c$_WEB_NL"
            done <<EOF_AW
$(_web_expand_pattern "$_aw_pat")
EOF_AW
        fi
        _aw_stack="$_aw_kids$_aw_next${_aw_stack:+$_WEB_NL$_aw_stack}"
    done
}

apache_extra_confs() {
    _main=$(apache_conf_path) || return 1
    _apache_walk "$_main" "$(apache_server_root "$_main")" | cut -f1 | \
        awk -v m="$_main" '!s[$0]++ && $0 != m && $0 != "!trunc"'
}

# apache_conf_stream -> 실제 로드 순서대로 펼친 설정 "파일<TAB>줄번호<TAB>내용"(같은 지시자가 여러 번 나오면
# 마지막 값이 적용되는 항목 - ServerTokens 등 - 은 이 순서로 판정해야 한다)
apache_conf_stream() {
    _main=$(apache_conf_path) || return 1
    _apache_walk "$_main" "$(apache_server_root "$_main")"
}

nginx_conf_path() {
    for p in /etc/nginx/nginx.conf /usr/local/nginx/conf/nginx.conf /usr/local/etc/nginx/nginx.conf /opt/nginx/conf/nginx.conf; do
        [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

# nginx_extra_confs — nginx.conf 가 "실제로" include 하는 파일만 찾아 반환한다(메인 제외, Apache 와 동일한
# 이유로 디렉터리 전체를 훑지 않는다). 상대 경로 include 는 nginx 설정 폴더(메인 설정의 폴더) 기준이다 -
# 예전에는 진단 실행 위치(작업 디렉터리) 기준으로 풀어 "include mime.types;" 류를 놓쳤다(WEB-R6).
# 한 줄에 여러 지시자가 있어도 include 를 찾고, 주석(#)은 제외, 순환·폭주는 Apache 와 같은 상한.
_nginx_walk() {
    _nw_base=$(dirname "$1"); _nw_stack="0|$1"; _nw_seen="$1"; _nw_loads=0
    while [ -n "$_nw_stack" ]; do
        _nw_top=${_nw_stack%%"$_WEB_NL"*}
        case "$_nw_stack" in *"$_WEB_NL"*) _nw_stack=${_nw_stack#*"$_WEB_NL"} ;; *) _nw_stack="" ;; esac
        _nw_depth=${_nw_top%%|*}; _nw_file=${_nw_top#*|}
        printf '%s\n' "$_nw_file"
        _nw_kids=""
        while IFS= read -r _nw_pat; do
            [ -n "$_nw_pat" ] || continue
            if [ "$_nw_depth" -ge 16 ] || [ "$_nw_loads" -ge 512 ]; then
                printf '!trunc\n'; break
            fi
            case "$_nw_pat" in /*) ;; *) _nw_pat="$_nw_base/$_nw_pat" ;; esac
            while IFS= read -r _nw_c; do
                [ -n "$_nw_c" ] || continue
                case "$_WEB_NL$_nw_seen$_WEB_NL" in *"$_WEB_NL$_nw_c$_WEB_NL"*) continue ;; esac
                _nw_seen="$_nw_seen$_WEB_NL$_nw_c"; _nw_loads=$((_nw_loads + 1))
                _nw_kids="$_nw_kids$((_nw_depth + 1))|$_nw_c$_WEB_NL"
            done <<EOF_NW2
$(_web_expand_pattern "$_nw_pat")
EOF_NW2
        done <<EOF_NW1
$(awk '{ sub(/\r$/, ""); sub(/#.*/, ""); s = $0
         while (match(s, /(^|[ \t;{}])include[ \t]+[^;]+;/)) {
             p = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
             sub(/^[ \t;{}]*include[ \t]+/, "", p); sub(/[ \t]*;$/, "", p); gsub(/"/, "", p); print p } }' "$_nw_file" 2>/dev/null)
EOF_NW1
        _nw_stack="$_nw_kids$_nw_stack"
    done
}

nginx_extra_confs() {
    _main=$(nginx_conf_path) || return 1
    _nginx_walk "$_main" | awk -v m="$_main" '!s[$0]++ && $0 != m && $0 != "!trunc"'
}

# web_conf_files <apache|nginx> -> 실제 로드되는 설정 파일(메인 포함) 목록.
# rc 1 = 메인 설정을 찾지 못함, 2 = 읽을 수 없는 설정 파일이 있거나 Include 상한에 걸림(목록은 그래도 출력).
web_conf_files() {
    case $1 in
        apache) _wcf_main=$(apache_conf_path) || return 1
                _wcf_list=$(_apache_walk "$_wcf_main" "$(apache_server_root "$_wcf_main")" | cut -f1 | awk '!s[$0]++') ;;
        nginx) _wcf_main=$(nginx_conf_path) || return 1
               _wcf_list=$(_nginx_walk "$_wcf_main" | awk '!s[$0]++') ;;
        *) return 1 ;;
    esac
    _wcf_rc=0
    while IFS= read -r _wcf_f; do
        case "$_wcf_f" in
            "") ;;
            '!trunc') _wcf_rc=2 ;;
            *) [ -r "$_wcf_f" ] || _wcf_rc=2; printf '%s\n' "$_wcf_f" ;;
        esac
    done <<EOF_WCF
$_wcf_list
EOF_WCF
    return $_wcf_rc
}

# web_load_conf <apache|nginx> -> WEB_FILES(공백 구분 설정 파일 목록) 설정. 엔진이 감지됐는데 설정을 찾거나
# 읽지 못하면 "확인 못 함"이다(S6, 진단 검수 WEB-R3) - 호출 측 errors 변수에 사유를 붙인다.
# 메인 설정을 못 찾으면 1(이 엔진 판정 생략), 일부 파일만 못 읽으면 0(찾은 위반은 그대로 VULN, 없으면 ERROR).
web_load_conf() {
    WEB_FILES=$(web_conf_files "$1")
    case $? in
        0) return 0 ;;
        2) errors="${errors:-} $1(읽을 수 없는 설정 파일이 있거나 Include 상한 초과)"; return 0 ;;
        *) WEB_FILES=""; errors="${errors:-} $1(설정 파일을 찾지 못함)"; return 1 ;;
    esac
}

# web_finish <VULN 문구> <GOOD 문구> [MANUAL 문구] -- 엔진별 판정 변수(checked/violations/errors/manuals/evidence)를
# 종합한다. VULN(하나라도 위반) > ERROR(설정을 확인하지 못한 엔진 - S6) > MANUAL > GOOD, 대상 엔진이 없으면 NA.
web_finish() {
    if [ "${checked:-0}" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "${violations:-}" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="$1:$violations${errors:+ / 확인하지 못한 엔진:$errors}"
    elif [ -n "${errors:-}" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="설정을 확인하지 못한 엔진이 있어 양호로 판정할 수 없음:$errors${manuals:+ / 수동 확인:$manuals}"
    elif [ -n "${manuals:-}" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="${3:-자동 판정이 제한적인 엔진 존재}:$manuals"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="$2"
    fi
    CHECK_EVIDENCE="${evidence:-}"
}

# web_mask_xml_secrets (stdin -> stdout) -- Tomcat XML 증적에서 비밀번호류 속성 값(keystorePass,
# truststorePass, certificateKeystorePassword, password, secret 등)을 **** 로 가린다(S5, 진단 검수 WEB-R9).
web_mask_xml_secrets() {
    sed -E "s/([A-Za-z]*([Pp]ass|[Pp]assword|[Ss]ecret|[Pp]wd))([[:space:]]*=[[:space:]]*)(\"[^\"]*\"|'[^']*')/\\1\\3\"****\"/g"
}

# web_mask_url_secrets (stdin -> stdout) -- Apache/Nginx 설정 줄 증적(ProxyPass·proxy_pass·Redirect 등)에 든 URL 의
# 사용자 정보(scheme://user:pass@)와 비밀류 쿼리 값(token/key/password/secret/auth 등)을 **** 로 가린다(S5, 1.3.3).
web_mask_url_secrets() {
    sed -E 's#(://)[^/@[:space:]"'"'"']+@#\1****@#g; s/([?&;]([A-Za-z_]*([Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][A-Za-z]*|[Pp][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Uu][Tt][Hh][A-Za-z]*|[Ss][Ii][Gg][A-Za-z]*))=)[^&[:space:]"'"'"';]*/\1****/g'
}

# web_apache_option_hits <옵션> <파일...> -> 옵션이 켜진(무표기·+옵션·All) 주석 아닌 Options 줄을 "파일:줄: 내용"
# 으로 출력. All 은 MultiViews 를 뺀 모든 옵션(Indexes·Includes·FollowSymLinks·ExecCGI)을 켠다(진단 검수 WEB-R10).
# Includes 는 IncludesNOEXEC 도 SSI 활성으로 본다. -옵션(무효화)은 당연히 제외한다.
web_apache_option_hits() {
    _wao_opt=$1; shift
    [ $# -gt 0 ] || return 0
    awk -v tok="$_wao_opt" '
        BEGIN { tok = tolower(tok) }
        { body = $0; sub(/\r$/, "", body); sub(/^[ \t]+/, "", body); n = split(body, a, /[ \t]+/)
          if (n >= 1 && tolower(a[1]) == "options")
              for (i = 2; i <= n; i++) {
                  w = tolower(a[i]); sub(/^\+/, "", w)
                  if (w == tok || w == "all" || (tok == "includes" && w == "includesnoexec")) { print FILENAME ":" FNR ": " body; break }
              } }' "$@" 2>/dev/null
}

# apache_last_directive <지시자> -> 실제 로드 순서상 마지막(=적용되는) 주석 아닌 지시자를 "값<TAB>파일:줄: 내용"
# 으로 출력(없으면 빈 출력). ServerTokens 처럼 마지막 값이 이기는 지시자용 - "어딘가에 Prod 가 있으면 양호"로
# 보면 Debian conf-enabled/security.conf 의 "ServerTokens OS" 가 나중에 덮어써도 GOOD 이 된다(진단 검수 WEB-R11).
apache_last_directive() {
    apache_conf_stream | awk -v d="$1" '
        BEGIN { d = tolower(d) }
        { t = $0; f = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); sub(/^[ \t]+/, "", t)
          n = split(t, a, /[ \t]+/)
          if (n >= 1 && tolower(a[1]) == d) { split(f, h, "\t"); v = (n >= 2 ? a[2] : ""); gsub(/"/, "", v); last = v "\t" h[1] ":" h[2] ": " t } }
        END { if (last != "") print last }'
}

# web_log_dirs <apache|nginx|tomcat> -> 로그 폴더(존재하는 것만, 실제 경로로 중복 제거). 대표 경로 + 설정의
# ErrorLog/CustomLog(Apache, 상대 경로는 ServerRoot 기준)·error_log/access_log(Nginx) 의 폴더.
# 변수(${APACHE_LOG_DIR})·파이프(|)·syslog·/dev/·/proc/(공식 httpd 이미지의 /proc/self/fd/2) 대상은 건너뛴다. RHEL(/var/log/httpd, /var/log/tomcat) 포함(WEB-R11).
web_log_dirs() {
    _wld_cfg=""
    case $1 in
        apache)
            _wld="/usr/local/apache2/logs /var/log/apache2 /var/log/httpd"
            if _wld_main=$(apache_conf_path); then
                _wld_root=$(apache_server_root "$_wld_main")
                _wld_cfg=$(apache_conf_stream 2>/dev/null | awk -v r="$_wld_root" '
                    { t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); sub(/^[ \t]+/, "", t); n = split(t, a, /[ \t]+/); k = tolower(a[1])
                      if ((k == "errorlog" || k == "customlog" || k == "transferlog") && n >= 2) {
                          p = a[2]; gsub(/"/, "", p)
                          if (p ~ /[$|]/ || p ~ /^syslog/ || p ~ /^\/(dev|proc)\//) next
                          if (p !~ /^\//) p = r "/" p
                          sub(/\/[^\/]*$/, "", p); print p } }')
            fi ;;
        nginx)
            _wld="/var/log/nginx /usr/local/nginx/logs"
            _wld_cfg=$(web_conf_files nginx 2>/dev/null | while IFS= read -r _wld_f; do
                awk '{ sub(/#.*/, ""); s = $0
                       while (match(s, /(access|error)_log[ \t]+[^ \t;]+/)) {
                           p = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH); sub(/^[^ \t]+[ \t]+/, "", p); gsub(/"/, "", p)
                           if (p ~ /^\// && p !~ /^\/(dev|proc)\// && p !~ /[$]/) { sub(/\/[^\/]*$/, "", p); print p } } }' "$_wld_f" 2>/dev/null
            done) ;;
        tomcat)
            _wld="/var/log/tomcat /var/log/tomcat9 /var/log/tomcat10"
            _wld_h=$(tomcat_home) && _wld="$_wld_h/logs $_wld" ;;
        *) return 1 ;;
    esac
    for _wld_d in $_wld $_wld_cfg; do
        [ -d "$_wld_d" ] && (cd "$_wld_d" 2>/dev/null && pwd -P)
    done | awk '!s[$0]++'
}

# tomcat_pids -> Tomcat(org.apache.catalina.startup.Bootstrap) java 프로세스 PID 목록. 다른 java 프로세스
# (Elasticsearch 등)를 Tomcat 으로 보지 않는다(진단 검수 WEB-R10).
tomcat_pids() {
    for _tp in $(proc_pids_by_comm java); do
        tr '\000' '\n' 2>/dev/null < "/proc/$_tp/cmdline" | grep -qx 'org\.apache\.catalina\.startup\.Bootstrap' && echo "$_tp"
    done
}

# tomcat_home — Tomcat 인스턴스 경로(CATALINA_BASE: conf/·logs/·webapps/ 가 있는 곳).
# 1) 실행 중인 Tomcat 의 -Dcatalina.base=  2) CATALINA_BASE·CATALINA_HOME 환경변수  3) 대표 경로
# (Debian 은 /var/lib/tomcatN 이 BASE 이고 /usr/share/tomcatN 은 HOME 이라 conf/ 가 없다 - BASE 를 먼저 본다,
# RHEL 은 /usr/share/tomcat/conf -> /etc/tomcat). conf/ 폴더가 있는 경로만 인정한다(진단 검수 WEB-R4).
tomcat_home() {
    for _th_pid in $(tomcat_pids); do
        _th_b=$(tr '\000' '\n' 2>/dev/null < "/proc/$_th_pid/cmdline" | sed -n 's/^-Dcatalina\.base=//p' | head -n 1)
        [ -n "$_th_b" ] && [ -d "$_th_b/conf" ] && { echo "$_th_b"; return 0; }
    done
    for _th_d in "${CATALINA_BASE:-}" "${CATALINA_HOME:-}" /usr/local/tomcat /opt/tomcat /var/lib/tomcat10 /var/lib/tomcat9 \
                 /var/lib/tomcat /usr/share/tomcat /usr/share/tomcat10 /usr/share/tomcat9; do
        [ -n "$_th_d" ] && [ -d "$_th_d/conf" ] && { echo "$_th_d"; return 0; }
    done
    return 1
}

# tomcat_conf_dir -> Tomcat conf 폴더(tomcat_home/conf, 없으면 RHEL·Debian 의 /etc/tomcat*). 못 찾으면 1.
tomcat_conf_dir() {
    _tcd_h=$(tomcat_home) && { echo "$_tcd_h/conf"; return 0; }
    for _tcd in /etc/tomcat /etc/tomcat10 /etc/tomcat9; do
        [ -f "$_tcd/server.xml" ] && { echo "$_tcd"; return 0; }
    done
    return 1
}

# web_load_tomcat_conf <파일명> -> TC_FILE 설정. conf 폴더를 못 찾거나 파일이 없거나 읽지 못하면 호출 측
# errors 변수에 사유를 붙이고 1(예전에는 이때 검사할 파일이 없어 GOOD 이 나왔다 - 진단 검수 WEB-R3).
web_load_tomcat_conf() {
    TC_FILE=""
    _wlt_dir=$(tomcat_conf_dir) || { errors="${errors:-} tomcat(설치 경로·conf 폴더를 찾지 못함)"; return 1; }
    TC_FILE="$_wlt_dir/$1"
    [ -f "$TC_FILE" ] || { errors="${errors:-} tomcat($TC_FILE 없음)"; return 1; }
    [ -r "$TC_FILE" ] || { errors="${errors:-} tomcat($TC_FILE 읽기 불가)"; return 1; }
    return 0
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

# ---- XML 주석 제거 (Tomcat/JEUS 등 XML 설정 파일 파싱 전 필수) ----------------
# Tomcat 기본 tomcat-users.xml 은 예시 관리자 계정이 <!-- ... --> 주석으로 감싸진 채 배포되며,
# grep 만으로 검색하면 "파일에 텍스트가 있다"와 "실제로 활성화된 설정이다"를 구분하지 못해
# 주석 처리된 계정을 활성 계정으로 오판하는 실제 버그가 있었다(03_web WEB-01을 Docker 컨테이너로
# 검증하다 발견). XML/설정 파일을 grep 하기 전에는 항상 이 함수로 주석을 먼저 제거한다.
strip_xml_comments() {
    awk '
    {
        line = $0
        out = ""
        while (1) {
            if (incomment) {
                end = index(line, "-->")
                if (end > 0) { line = substr(line, end + 3); incomment = 0 }
                else { line = ""; break }
            } else {
                start = index(line, "<!--")
                if (start > 0) { out = out substr(line, 1, start - 1); line = substr(line, start + 4); incomment = 1 }
                else { out = out line; line = ""; break }
            }
        }
        print out
    }
    ' "$1" 2>/dev/null
}

# ---- DBMS 공통: 엔진 탐지 (08_dbms) -----------------------------------------
# 로컬에서 구동 중인 DBMS 데몬을 /proc 기반으로 탐지한다 (ps/pgrep 미존재 이미지 대응,
# 03_web 에서 검증된 방식 재사용). 여러 엔진이 동시에 감지되면 DBMS_ENGINE 을 비워
# run.sh 가 -e 로 명시적으로 선택하도록 안내한다 (DBMS는 엔진별 카탈로그/권한 체계가
# 완전히 달라 Web처럼 여러 엔진을 한 번에 합산 진단하지 않는다).
detect_dbms_engine() {
    _found=""
    [ -n "$(proc_pids_by_comm mysqld)" ] && _found="$_found mysql"
    [ -n "$(proc_pids_by_comm postgres)" ] && _found="$_found postgres"
    _found=$(printf '%s' "$_found" | awk '{$1=$1};1')
    _count=$(printf '%s\n' "$_found" | wc -w | tr -d ' ')
    if [ "$_count" -eq 1 ]; then
        DBMS_ENGINE="$_found"
    else
        DBMS_ENGINE=""
        DBMS_ENGINES_FOUND="$_found"
    fi
}

# ---- DBMS 공통: 운영 안전장치 (무기한 대기·계정 잠금 방지) ------------------------
# 1) 모든 DB 클라이언트 호출은 _db_run 으로 감싸 DB_CMD_TIMEOUT 초 안에 끝나지 않으면 중단한다.
#    timeout 명령이 없는 환경에서는 그대로 실행한다(대상 무설치 원칙). timeout 이 감싼 자식은
#    TTY 를 읽을 수 없어 비밀번호 프롬프트로 멈추는 일도 함께 막힌다.
# 2) run.sh 가 db_preflight 로 접속을 딱 1번 시험해 실패하면 DB_CONN_FAILED=1 을 세운다. 이후
#    *_query 는 접속을 시도하지 않고 사유만 DB_ERR_FILE 에 남긴다 - 잘못된 비밀번호로 항목 수
#    (최대 18회)만큼 로그인을 반복해 Oracle FAILED_LOGIN_ATTEMPTS(기본 10회)·MSSQL CHECK_POLICY
#    등으로 운영 계정이 잠기는 것을 막는다.
# DB_CMD_TIMEOUT=0 이면 제한하지 않는다 - 인스턴스 재기동(SHUTDOWN/STARTUP)처럼 도중에 끊으면
# DB가 내려간 채로 남는 조치에서만 쓴다(fixes/oracle/D-19·D-26).
DB_CMD_TIMEOUT=${DB_CMD_TIMEOUT:-120}

_db_run() {
    if [ "$DB_CMD_TIMEOUT" != "0" ] && command -v timeout >/dev/null 2>&1; then
        timeout "$DB_CMD_TIMEOUT" "$@"
        _dbr_rc=$?
        [ "$_dbr_rc" -eq 124 ] && printf 'DB 명령이 %s초 안에 끝나지 않아 중단함(무기한 대기 방지)\n' "$DB_CMD_TIMEOUT" >&2
        return "$_dbr_rc"
    fi
    "$@"
}

_db_conn_blocked() {
    [ "${DB_CONN_FAILED:-0}" = "1" ] || return 1
    printf 'DB 접속 사전 점검 실패로 접속하지 않음(계정 잠금 방지): %s\n' "${DB_CONN_FAIL_MSG:-}" > "${DB_ERR_FILE:-/dev/null}"
    return 0
}

# Oracle 비밀번호 만료 "예고" 경고(실패 아님): 28002·28011(구버전), 28098(23ai 이상)
ORACLE_PW_WARN_RE='^ORA-(28002|28011|28098)'

# db_preflight  -- DBMS_ENGINE 에 맞춰 접속을 1회 시험. 실패 시 0이 아닌 값 반환 + DB_CONN_FAILED=1
db_preflight() {
    DB_CONN_FAILED=0; DB_CONN_FAIL_MSG=""
    case "${DBMS_ENGINE:-}" in
        mysql) _pf_out=$(mysql_query "SELECT 1;"); _pf_rc=$? ;;
        postgres) _pf_out=$(psql_query "SELECT 1;"); _pf_rc=$? ;;
        oracle)
            # 1단계: connect 한 줄만 보내고 표준입력을 바로 닫는다(진단 검수 D-R11). 비밀번호가 만료(ORA-28001)
            # 되면 sqlplus 가 "New password:" 를 표준입력에서 읽는데, 예전처럼 connect 뒤에 SET/SELECT 줄이 이어지면
            # 그 줄이 새 비밀번호로 읽힐 여지가 있었다. 여기서는 EOF 만 읽혀 비밀번호는 바뀌지 않는다. 접속 실패면
            # 이 1회로 끝나고(S3), 성공했을 때만 2단계 SELECT 로 넘어간다.
            _pf_out=$( { printf 'whenever sqlerror exit sql.sqlcode\n'
                         printf 'whenever oserror exit failure\n'
                         oracle_connect_line; } | _db_run sqlplus -s /nolog 2>"${DB_ERR_FILE:-/dev/null}" )
            _pf_rc=$?
            if printf '%s\n' "$_pf_out" | grep -qE 'ORA-28001|ORA-28000'; then
                _pf_rc=1
            elif [ "$_pf_rc" -eq 0 ] && printf '%s\n' "$_pf_out" | grep -vE "$ORACLE_PW_WARN_RE" | grep -qE '^(ORA-[0-9]+|SP2-[0-9]+)'; then
                _pf_rc=1
            fi
            if [ "$_pf_rc" -eq 0 ]; then
                _pf_out=$(oracle_query "SELECT 1 FROM dual;"); _pf_rc=$?
            fi
            ;;
        *) return 0 ;;
    esac
    if [ "$_pf_rc" -ne 0 ]; then
        DB_CONN_FAILED=1
        DB_CONN_FAIL_MSG=$( { head -n 1 "${DB_ERR_FILE:-/dev/null}"
                              printf '%s\n' "$_pf_out" | grep -E '^(ORA-|SP2-)' | head -n 1; } 2>/dev/null | tr '\n' ' ')
    fi
    export DB_CONN_FAILED DB_CONN_FAIL_MSG
    return "$_pf_rc"
}

# ---- DBMS 공통: 원격 모드 판별 (진단 검수 D-R1) ---------------------------------------
# --host 로 다른 서버에 접속하면 DB 조회는 원격 서버를 보지만, 설정 파일(my.cnf·pg_hba.conf·sqlnet.ora)·
# 프로세스(/proc)는 이 스크립트를 실행한 PC 의 것을 읽는다. 예전에는 분석자 PC(또는 클라이언트 컨테이너)의
# /etc/my.cnf 권한으로 D-14 를 VULN/GOOD 판정했다. 원격이면 해당 항목은 MANUAL 로 돌린다.
# db_is_remote  -- DB_HOST 가 비었거나 이 호스트 자신(이름·IP·루프백)이면 1(로컬), 아니면 0(원격)
db_is_remote() {
    _dr_h=${DB_HOST:-}
    _dr_h=${_dr_h#[}; _dr_h=${_dr_h%]}
    case "$_dr_h" in
        ""|localhost|localhost.localdomain|127.*|::1|0:0:0:0:0:0:0:1) return 1 ;;
    esac
    _dr_self=$( { hostname; hostname -f; hostname -s; hostname -I | tr ' ' '\n'
                  ip -o addr show | awk '{sub(/\/.*/, "", $4); print $4}'; } 2>/dev/null | awk 'NF')
    printf '%s\n' "$_dr_self" | grep -qixF -- "$_dr_h" && return 1
    # 이름이 이 호스트 IP 로 풀리면 로컬(예: --host db01.example.com 이 자기 자신). 조회는 5초 제한.
    for _dr_ip in $(run_to 5 getent hosts "$_dr_h" 2>/dev/null | awk '{print $1}'); do
        case "$_dr_ip" in 127.*|::1) return 1 ;; esac
        printf '%s\n' "$_dr_self" | grep -qixF -- "$_dr_ip" && return 1
    done
    return 0
}

# db_remote_skip <확인 대상 설명>  -- 원격 모드면 CHECK_* 를 MANUAL 로 채우고 0 반환(호출 check 는 return).
# DB_REMOTE 는 run.sh 가 한 번 계산해 export 하고, 없으면(fix.sh 재검증 등) 여기서 계산한다.
db_remote_skip() {
    if [ -z "${DB_REMOTE:-}" ]; then
        if db_is_remote; then DB_REMOTE=1; else DB_REMOTE=0; fi
    fi
    [ "$DB_REMOTE" = "1" ] || return 1
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="원격 모드 - DB 서버 호스트에서 실행 필요: $1 은(는) DB 서버의 로컬 정보라 이 PC(--host ${DB_HOST:-})에서 확인할 수 없음"
    CHECK_EVIDENCE=""
    return 0
}

# ---- DBMS 공통: 접속 계정 권한 사전 확인 (진단 검수 D-R2/D-R5) ------------------------------
# 관리자가 아닌 계정은 카탈로그에서 자기 행만 보거나(information_schema·role_table_grants) 설정 경로
# 조회(SHOW hba_file)를 거부당해, "없음"을 GOOD 으로 읽는 거짓 양호가 났다. preflight 성공 뒤 1회 확인해
# DB_PRIV_LIMITED(항목 코드 목록)·DB_PRIV_MSG·DB_PRIV_STATUS 를 세운다 - run.sh 가 이 항목들의 판정을
# DB_PRIV_STATUS(기본 ERROR)로 바꾼다. 확인 쿼리 자체가 실패해도 "권한 부족"으로 본다(MSSQL 과 동일).
db_privilege_check() {
    DB_PRIV_LIMITED=""; DB_PRIV_MSG=""; DB_PRIV_STATUS="ERROR"
    [ "${DB_CONN_FAILED:-0}" = "1" ] && return 0
    case "${DBMS_ENGINE:-}" in
        mysql)
            if ! mysql_query "SELECT 1 FROM mysql.user LIMIT 1;" >/dev/null 2>&1; then
                DB_PRIV_LIMITED="D-01 D-02 D-04 D-06 D-08 D-10 D-11 D-21"
                DB_PRIV_MSG="접속 계정이 mysql.user 를 읽을 수 없음(관리자 권한 아님)"
            fi ;;
        postgres)
            _pc=$(psql_query "SELECT rolsuper::text || '|' || pg_has_role(current_user, 'pg_read_all_settings', 'USAGE')::text FROM pg_roles WHERE rolname = current_user;" 2>/dev/null | tr -d ' \t\r')
            case "$_pc" in
                true\|*) : ;;
                false\|true)
                    DB_PRIV_LIMITED="D-01 D-08 D-11"
                    DB_PRIV_MSG="접속 계정이 superuser 가 아님(pg_shadow·pg_authid 미조회, role_table_grants 는 자기 관련 행만 보임)" ;;
                *)
                    DB_PRIV_LIMITED="D-01 D-03 D-08 D-10 D-11 D-14"
                    DB_PRIV_MSG="접속 계정이 superuser·pg_read_all_settings 가 아님(설정 경로·일부 설정값·권한 카탈로그 미조회)" ;;
            esac ;;
        oracle)
            # CDB$ROOT 로 접속하면 dba_* 뷰가 루트 컨테이너만 보여 PDB 의 계정·객체가 빠진다(진단 검수 D-R5).
            _con=$(oracle_query "SELECT sys_context('USERENV','CON_NAME') FROM dual;" 2>/dev/null | tr -d ' \t\r' | awk 'NF' | head -n 1)
            if [ "$_con" = "CDB\$ROOT" ]; then
                _npdb=$(oracle_query "SELECT COUNT(*) FROM v\$pdbs WHERE name <> 'PDB\$SEED';" 2>/dev/null | tr -d ' \t\r' | awk 'NF' | head -n 1)
                if [ -n "$_npdb" ] && [ "$_npdb" != "0" ]; then
                    DB_PRIV_LIMITED="D-01 D-02 D-03 D-04 D-05 D-06 D-09 D-11 D-17 D-18 D-20 D-21"
                    DB_PRIV_MSG="CDB\$ROOT 에 접속함 - PDB(${_npdb}개)의 계정·객체는 조회되지 않음. PDB 서비스명(--db)으로 각각 다시 진단 필요"
                    DB_PRIV_STATUS="MANUAL"
                fi
            fi ;;
    esac
    export DB_PRIV_LIMITED DB_PRIV_MSG DB_PRIV_STATUS
}

# db_privilege_apply <code>  -- run.sh 루프에서 check 직후 호출. DB_PRIV_LIMITED 에 든 항목의 GOOD/VULN/MANUAL 을
# DB_PRIV_STATUS 로 바꾸고 원래 판정은 detail 에 남긴다. CDB$ROOT(DB_PRIV_STATUS=MANUAL)는 루트에서 찾은 취약은
# 그 자체로 사실이므로 GOOD 만 바꾼다(Oracle 실기: 루트의 OPEN 기본 계정 VULN 을 MANUAL 로 덮던 문제).
db_privilege_apply() {
    [ -n "${DB_PRIV_LIMITED:-}" ] || return 0
    case " $DB_PRIV_LIMITED " in *" $1 "*) ;; *) return 0 ;; esac
    case "$CHECK_STATUS" in
        GOOD|VULN|MANUAL)
            [ "$DB_PRIV_STATUS" = "MANUAL" ] && [ "$CHECK_STATUS" != "GOOD" ] && return 0
            CHECK_DETAIL="$DB_PRIV_MSG - 전체 정보를 보지 못해 판정 불가(일부만 보고 내린 판정: $CHECK_STATUS - $CHECK_DETAIL)"
            CHECK_STATUS="$DB_PRIV_STATUS" ;;
    esac
}

# ---- DBMS 공통: MySQL 연결/쿼리 ---------------------------------------------
# 접속 정보는 run.sh 가 파싱한 DB_HOST/DB_PORT/DB_USER/DB_SOCKET 환경변수를 사용하고,
# 비밀번호는 절대 인자로 노출하지 않고 MYSQL_PWD 환경변수로만 전달한다
# (08_dbms/CLAUDE.md "접속정보 취급" 원칙). DB_ERR_FILE 은 run.sh 가 mktemp 로 준비한다.
mysql_args() {
    _a="-N -B --connect-timeout=5"
    [ -n "${DB_HOST:-}" ] && _a="$_a -h $DB_HOST"
    [ -n "${DB_PORT:-}" ] && _a="$_a -P $DB_PORT"
    [ -n "${DB_USER:-}" ] && _a="$_a -u $DB_USER"
    [ -n "${DB_SOCKET:-}" ] && _a="$_a -S $DB_SOCKET"
    printf '%s' "$_a"
}

# mysql_query <sql>  -- 결과를 탭 구분으로 stdout 에 출력, 실패 시 0이 아닌 값 반환
mysql_query() {
    _db_conn_blocked && return 1
    (
        [ -n "${DB_PASSWORD:-}" ] && export MYSQL_PWD="$DB_PASSWORD"
        # shellcheck disable=SC2046
        _db_run mysql $(mysql_args) -e "$1"
    ) 2>"${DB_ERR_FILE:-/dev/null}"
}

mysql_config_path() {
    for _f in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf \
              /etc/mysql/mariadb.conf.d/50-server.cnf; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

# ---- DBMS 공통: PostgreSQL 연결/쿼리 ----------------------------------------
# -w: 비밀번호가 필요해도 프롬프트를 띄우지 않고 즉시 실패(대화형 대기 방지).
psql_args() {
    _a="-X -q -t -A -w --no-psqlrc"
    [ -n "${DB_HOST:-}" ] && _a="$_a -h $DB_HOST"
    [ -n "${DB_PORT:-}" ] && _a="$_a -p $DB_PORT"
    [ -n "${DB_USER:-}" ] && _a="$_a -U $DB_USER"
    _a="$_a -d ${DB_NAME:-postgres}"
    printf '%s' "$_a"
}

# psql_query <sql>  -- 결과를 |로 구분된 행으로 stdout 에 출력, 실패 시 0이 아닌 값 반환
# 쿼리 시간 제한은 PGOPTIONS(statement_timeout) 대신 _db_run 으로 건다 - pgbouncer 경유
# 접속은 options 시작 파라미터를 거부해 접속 자체가 실패할 수 있기 때문.
psql_query() {
    _db_conn_blocked && return 1
    (
        [ -n "${DB_PASSWORD:-}" ] && export PGPASSWORD="$DB_PASSWORD"
        export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
        # shellcheck disable=SC2046
        _db_run psql $(psql_args) -c "$1"
    ) 2>"${DB_ERR_FILE:-/dev/null}"
}

postgres_config_path() {
    _cf=$(psql_query "SHOW config_file;" 2>/dev/null | tr -d '\r' | awk '{$1=$1};1')
    if [ -n "$_cf" ] && [ -f "$_cf" ]; then printf '%s' "$_cf"; return; fi
    for _f in /var/lib/postgresql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf \
              /etc/postgresql/*/main/postgresql.conf; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

postgres_hba_path() {
    _hf=$(psql_query "SHOW hba_file;" 2>/dev/null | tr -d '\r' | awk '{$1=$1};1')
    if [ -n "$_hf" ] && [ -f "$_hf" ]; then printf '%s' "$_hf"; return; fi
    for _f in /var/lib/postgresql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf \
              /etc/postgresql/*/main/pg_hba.conf; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

# postgres_other_dbs_manual  -- 접속한 DB 하나만 보고 GOOD 을 낸 check 가 호출한다. 접속 가능한 다른 DB 가
# 있으면 CHECK_STATUS 를 MANUAL 로 바꾸고 그 목록을 남긴다(진단 검수 D-R7, D-11/D-20). 다른 DB 에 추가로
# 접속하지 않는 이유: pg_hba 가 DB 별로 달라 접속 실패(로그인 실패 기록)가 늘 수 있다(S3).
postgres_other_dbs_manual() {
    _odb=$(psql_query "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate AND datname <> current_database() ORDER BY datname;" 2>/dev/null)
    _odb_rc=$?
    if [ "$_odb_rc" -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="다른 데이터베이스 목록을 조회하지 못함 - 접속 DB 판정: $CHECK_DETAIL"
    elif [ -n "$_odb" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="접속한 DB(${DB_NAME:-postgres})에서는 양호: $CHECK_DETAIL - 다른 DB($(printf '%s' "$_odb" | tr '\n' ' '))는 확인하지 않음, --db 로 각각 진단 필요"
    fi
}

# ---- DBMS 공통: Oracle 연결/쿼리 --------------------------------------------
# 비밀번호는 sqlplus 인자(argv)로 절대 넘기지 않고, 접속 문자열을 표준입력(파이프)으로만
# 전달한다(ps 목록 노출 방지). DB_USER/DB_PASSWORD 미지정 시 OS 인증("/ as sysdba")으로 접속한다.
oracle_connect_line() {
    if [ -n "${DB_USER:-}" ] && [ -n "${DB_PASSWORD:-}" ]; then
        _target=""
        [ -n "${DB_HOST:-}" ] && _target="@//${DB_HOST}:${DB_PORT:-1521}/${DB_NAME:-FREE}"
        printf 'connect %s/%s%s\n' "$DB_USER" "$DB_PASSWORD" "$_target"
    else
        printf 'connect / as sysdba\n'
    fi
}

# oracle_query <sql>  -- 결과를 stdout 에 출력, 실패 시(SQL 오류/접속 실패) 0이 아닌 값 반환
# whenever 는 반드시 connect 보다 먼저 선언한다 - 뒤에 두면 접속 실패(ORA-01017 등)에 적용되지
# 않아 이후 SELECT 가 SP2-0640(Not connected)과 함께 rc=0 으로 끝나고, 오류 문구가 "결과 있음"으로
# 읽혀 거짓 VULN 이 난다. 같은 이유로 출력에 ORA-/SP2- 행이 있으면 실패로 본다.
oracle_query() {
    _db_conn_blocked && return 1
    _out=$(
        { printf 'whenever sqlerror exit sql.sqlcode\n'
          printf 'whenever oserror exit failure\n'
          oracle_connect_line
          printf 'set heading off feedback off pagesize 0 verify off linesize 500 trimspool on\n'
          printf 'set colsep |\n'
          printf '%s\n' "$1"
          printf 'exit\n'
        } | _db_run sqlplus -s /nolog 2>"${DB_ERR_FILE:-/dev/null}"
    )
    _rc=$?
    # ORA-28002/28011(구버전)·ORA-28098(23ai 이상)은 비밀번호 만료 예고로, 접속 성공 시 함께 찍히는 경고다 - 예전에는
    # 이 줄 때문에 전 항목이 ERROR 가 됐다(진단 검수 D-R11). 경고 블록("ERROR:" 머리줄, 이어지는 설명 줄, Help 링크)만
    # 지우고 판정한다 - 남기면 "결과 있음=취약" check 가 거짓 VULN 을 낸다. ORA-28001(만료)은 db_preflight 1단계에서 걸러진다.
    if printf '%s\n' "$_out" | grep -qE "$ORACLE_PW_WARN_RE"; then
        _out=$(printf '%s\n' "$_out" | grep -vE "$ORACLE_PW_WARN_RE"'|^ERROR:[[:space:]]*$|password will expire|^Help: https?://docs\.oracle\.com/error-help/db/ora-280(02|11|98)' | sed '/^[[:space:]]*$/d')
    fi
    if [ "$_rc" -eq 0 ] && printf '%s\n' "$_out" | grep -qE '^(ORA-[0-9]+|SP2-[0-9]+)'; then
        _rc=1
    fi
    printf '%s\n' "$_out"
    return $_rc
}

# oracle_profile_limits <'RES1','RES2'>  -- "프로파일|자원|실효값" 행 출력. DEFAULT 프로파일과, 잠기지 않은(OPEN)
# 계정이 쓰는 모든 프로파일을 대상으로 하고, 사용자 정의 프로파일의 LIMIT 'DEFAULT' 는 DEFAULT 프로파일 값으로
# 풀어 쓴다. 예전에는 DEFAULT 프로파일만 봐서 실제 계정에 붙은 사용자 정의 프로파일이 UNLIMITED 여도 양호였다
# (진단 검수 D-R5, D-03/05/09).
oracle_profile_limits() {
    oracle_query "SELECT p.profile || '|' || p.resource_name || '|' || CASE WHEN p.limit = 'DEFAULT' THEN d.limit ELSE p.limit END FROM dba_profiles p JOIN dba_profiles d ON d.profile = 'DEFAULT' AND d.resource_name = p.resource_name WHERE p.resource_name IN ($1) AND (p.profile = 'DEFAULT' OR p.profile IN (SELECT profile FROM dba_users WHERE account_status = 'OPEN')) ORDER BY p.profile, p.resource_name;"
}

# oracle_profiles_unrestricted <'RES1','RES2'>  -- oracle_profile_limits 대상 프로파일 중, 주어진 자원의 실효값이
# 모두 미설정(UNLIMITED/NULL/빈 값)인 프로파일 이름을 공백으로 구분해 출력한다(checks/oracle/D-03·05·09 의 취약 판정과
# 같은 기준). 조회 실패 시 0이 아닌 값.
oracle_profiles_unrestricted() {
    _opu=$(oracle_profile_limits "$1") || return 1
    printf '%s\n' "$_opu" | awk -F'|' '
        NF >= 3 { p=$1; v=$3; gsub(/[ \t\r]/, "", p); gsub(/[ \t\r]/, "", v)
                  if (!(p in seen)) { seen[p]=1; order[++n]=p }
                  if (v != "" && v != "UNLIMITED" && v != "NULL") ok[p]=1 }
        END { for (i = 1; i <= n; i++) if (!(order[i] in ok)) printf "%s ", order[i] }'
}

# oracle_fix_profile_limits <'RES1','RES2'> <LIMIT 절>  -- 조치(fixes/oracle/D-03·05·09) 공통. 진단과 같은 범위(DEFAULT +
# OPEN 계정이 쓰는 사용자 정의 프로파일)에서 미설정 프로파일마다 ALTER PROFILE ... LIMIT <LIMIT 절> 을 적용한다(조치 후속
# F-R6 - 예전 조치는 DEFAULT 만 바꿔 사용자 정의 프로파일이 남아 재검증 VULN → 원복으로 끝났다). DEFAULT 를 먼저 고치고
# 다시 조회해, 값을 'DEFAULT' 로 상속하던 사용자 정의 프로파일은 건드리지 않는다(상속 유지). 원복 SQL 은 프로파일마다
# 조치 직전의 원래 값(상속이면 DEFAULT 키워드 그대로)으로 큐에 넣는다. FIX_STATUS/FIX_DETAIL/FIX_EVIDENCE 를 채운다.
oracle_fix_profile_limits() {
    FIX_EVIDENCE=""
    _ofp_bad=$(oracle_profiles_unrestricted "$1") || {
        FIX_STATUS="ERROR"; FIX_DETAIL="프로파일 조회 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; return
    }
    if [ -z "$_ofp_bad" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="미설정 프로파일이 없음(이미 정상)"; return
    fi
    _ofp_order=""
    for _ofp_p in $_ofp_bad; do
        if [ "$_ofp_p" = "DEFAULT" ]; then _ofp_order="DEFAULT $_ofp_order"; else _ofp_order="$_ofp_order $_ofp_p"; fi
    done
    _ofp_done=""
    for _ofp_p in $_ofp_order; do
        if [ "$_ofp_p" != "DEFAULT" ]; then
            # DEFAULT 를 고친 뒤 상속('DEFAULT')으로 해소된 프로파일은 건너뛴다
            _ofp_now=$(oracle_profiles_unrestricted "$1") || { FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }프로파일 재조회 실패"; return; }
            case " $_ofp_now " in *" $_ofp_p "*) ;; *) continue ;; esac
        fi
        case "$_ofp_p" in
            *\"*|*\'*) FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }처리할 수 없는 프로파일 이름: $_ofp_p"; return ;;
        esac
        if [ "$_ofp_p" = "DEFAULT" ]; then _ofp_id="DEFAULT"; else _ofp_id="\"$_ofp_p\""; fi
        _ofp_raw=$(oracle_query "SELECT resource_name || ' ' || limit FROM dba_profiles WHERE profile = '$_ofp_p' AND resource_name IN ($1) ORDER BY resource_name;") || {
            FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }$_ofp_p 현재 값 조회 실패"; return
        }
        _ofp_rb=$(printf '%s\n' "$_ofp_raw" | awk 'NF >= 2 { printf " %s %s", $1, $2 }')
        if [ -z "$_ofp_rb" ]; then
            FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }$_ofp_p 현재 값을 읽지 못해 원복할 수 없으므로 변경하지 않음"; return
        fi
        fix_db_queue_rollback "oracle" "ALTER PROFILE $_ofp_id LIMIT$_ofp_rb;"
        _ofp_out=$(oracle_query "ALTER PROFILE $_ofp_id LIMIT $2;" 2>&1) || {
            FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }ALTER PROFILE $_ofp_p 실패: $_ofp_out"; FIX_EVIDENCE="$_ofp_out"; return
        }
        _ofp_done="$_ofp_done $_ofp_p(변경 전:$_ofp_rb)"
    done
    FIX_STATUS="APPLIED"
    FIX_DETAIL="프로파일에 $2 설정함:$_ofp_done"
}

# oracle_conf_active <file>  -- .ora 파일에서 # 주석을 지운 내용을 출력(진단 검수 D-R6: 주석 처리된 설정을
# 유효한 설정으로 읽어 거짓 GOOD 이 났다). 읽지 못하면 0이 아닌 값 반환.
oracle_conf_active() {
    [ -r "$1" ] || return 1
    sed 's/#.*$//' "$1"
}

oracle_home() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -d "$ORACLE_HOME" ]; then printf '%s' "$ORACLE_HOME"; return; fi
    for _d in /opt/oracle/product/*/dbhome* /opt/oracle/product/*/db* \
              /u01/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/db_1; do
        [ -d "$_d" ] && { printf '%s' "$_d"; return; }
    done
}

oracle_sqlnet_ora() {
    _h=$(oracle_home)
    [ -n "$_h" ] && [ -f "$_h/network/admin/sqlnet.ora" ] && { printf '%s' "$_h/network/admin/sqlnet.ora"; return; }
    for _f in "${TNS_ADMIN:-}/sqlnet.ora" /etc/oracle/sqlnet.ora; do
        [ -n "$_f" ] && [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

oracle_listener_ora() {
    _h=$(oracle_home)
    [ -n "$_h" ] && [ -f "$_h/network/admin/listener.ora" ] && { printf '%s' "$_h/network/admin/listener.ora"; return; }
    for _f in "${TNS_ADMIN:-}/listener.ora" /etc/oracle/listener.ora; do
        [ -n "$_f" ] && [ -f "$_f" ] && { printf '%s' "$_f"; return; }
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
    _host=$(hostname 2>/dev/null || echo unknown-host)
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

# ============================================================================
# ---- 자동 조치(fix) 공통 (§자동 조치, 루트 CLAUDE.md 참고) -------------------
# ============================================================================
# 진단(run.*)과 완전히 분리된 fix.* 전용 헬퍼. run.* 는 절대 이 함수들을 쓰지 않는다.

# result.json(진단 결과)에서 status=VULN 인 코드 목록만 추출한다. result_add() 가 만드는
# 포맷은 guide.json 과 달리 항목당 한 줄에 compact JSON(들여쓰기 없음)으로 저장되므로
# guide_field() 와는 다른 파서가 필요하다.
result_list_vuln_codes() {
    _json=$1
    grep '"status":"VULN"' "$_json" | grep -o '"code":"[A-Z]*-[0-9]*"' | sed -E 's/.*"([A-Z]+-[0-9]+)".*/\1/'
}

# fix_prepare_dir <base_dir> <category_num> -> FIX_OUT_DIR/FIX_BACKUP_DIR/FIX_LOG 설정
fix_prepare_dir() {
    _base=$1; _cat_num=$2
    _host=$(hostname 2>/dev/null || echo unknown-host)
    _ts=$(date '+%Y%m%d-%H%M%S')
    FIX_OUT_DIR="${_base}/${_host}_${_cat_num}_fix_${_ts}-$$"
    FIX_BACKUP_DIR="$FIX_OUT_DIR/backup"
    make_private_dir "$FIX_OUT_DIR"
    make_private_dir "$FIX_BACKUP_DIR"
    FIX_LOG="$FIX_OUT_DIR/changes.log"
    # 감사 로그(운영 안전 기준 F6): 누가 언제 어느 호스트에서 바꿨는지 첫 줄에 남기고, 각 줄 앞에는
    # fix_log_stamp 가 시각을 붙인다(형식: 시각<TAB>코드<TAB>등급<TAB>결과<TAB>상세).
    printf '# 조치 실행 시작 %s / 호스트 %s / 실행자 %s(uid=%s, sudo=%s) / 도구 v%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %z')" "$_host" "$(id -un 2>/dev/null)" "$(id -u 2>/dev/null)" "${SUDO_USER:-없음}" "$TOOL_VERSION" > "$FIX_LOG"
}

# fix_log_stamp — 표준입력의 각 줄 앞에 시각을 붙인다(changes.log 기록용)
fix_log_stamp() {
    while IFS= read -r _ls; do printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_ls"; done
}

# fix_abort_item <사유> — 백업 실패처럼 "이대로 바꾸면 원복할 수 없는" 상황(운영 안전 기준 F1).
# 이 항목에서 이미 백업·변경한 것을 원복하고 조치 실행 전체를 중단한다(이후 항목도 바꾸지 않음).
# fixes/*.sh 는 run_fix 를 현재 셸에서 실행하므로 exit 가 fix.sh 전체를 끝낸다 - 그래서 fix_backup 을
# 파이프(| while)·$(...) 같은 서브셸 안에서 부르면 안 된다(here-doc 반복문을 쓸 것).
fix_abort_item() {
    log_error "[${FIX_CODE:-?}] $1 — 이 항목의 변경을 원복하고 조치 실행을 중단합니다(이후 항목은 변경하지 않음)."
    [ -n "${FIX_CODE:-}" ] && fix_rollback_item "$FIX_CODE"
    printf '%s\t-\tABORTED\t%s (이 항목 원복 후 실행 중단)%s\n' "${FIX_CODE:-?}" "$1" \
        "$(printf '%s' "${FIX_ROLLBACK_FAILS:-}" | tr '\n' ' ')" | fix_log_stamp >> "${FIX_LOG:-/dev/null}"
    exit 3
}

# fix_backup <파일경로> — 항목별(FIX_CODE) 백업 디렉터리에 원본을 상대경로 구조로 보존한다.
# 파일이 원래 존재하지 않았으면(조치가 "새로 생성"인 경우) .WAS_ABSENT 마커만 남겨
# 원복 시 삭제해야 함을 표시한다. fixes/<코드>.sh 는 파일을 고치기 전에 반드시 이 함수를 부른다.
# - 백업에 실패하면 변경하지 않고 중단한다(fix_abort_item). 예전에는 cp 실패를 무시하고 조치를
#   진행해, 디스크가 가득 찬 상황에서 잘린 백업으로 원복 시 원본을 덮어쓸 수 있었다.
# - 같은 항목에서 같은 경로를 다시 백업하면 첫 백업(조치 전 원본)을 보존하고 건너뛴다 - 예전에는
#   소유자를 바꾼 뒤 두 번째 백업이 첫 백업을 덮어써 원복해도 바뀐 상태가 남았다(U-24/U-31).
fix_backup() {
    _f=$1
    _rel=$(printf '%s' "$_f" | sed 's#^/##')
    _dest="$FIX_BACKUP_DIR/$FIX_CODE/$_rel"
    if [ -e "$_dest" ] || [ -e "$_dest.DIRMETA" ] || [ -e "$_dest.WAS_ABSENT" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$_dest")" 2>/dev/null || fix_abort_item "백업 디렉터리를 만들 수 없음: $(dirname "$_dest")"
    if [ -d "$_f" ]; then
        # 디렉터리는 내용 전체를 복사하지 않고(대부분의 조치는 디렉터리 자체의 소유자/권한만
        # 바꾸므로) 메타데이터(소유자·권한)만 기록해 원복 시 재적용한다. 소유자는 숫자(uid:gid)로
        # 남긴다 - 이름으로 남기면 소유자가 없는 디렉터리(U-15)는 "UNKNOWN" 이 되어 원복 chown 이 실패한다.
        _owner=$(stat -c '%u:%g' "$_f" 2>/dev/null)
        _perm=$(stat -c '%a' "$_f" 2>/dev/null)
        [ -n "$_owner" ] && [ -n "$_perm" ] || fix_abort_item "디렉터리 소유자/권한을 기록할 수 없음: $_f"
        printf '%s\n%s\n' "$_owner" "$_perm" > "$_dest.DIRMETA" 2>/dev/null || fix_abort_item "백업 기록 실패: $_f"
    elif [ -e "$_f" ]; then
        if ! cp -p "$_f" "$_dest.tmp" 2>/dev/null || ! mv "$_dest.tmp" "$_dest" 2>/dev/null; then
            rm -f "$_dest.tmp" "$_dest"
            fix_abort_item "백업 실패(디스크 공간·권한 확인): $_f"
        fi
        if command -v cmp >/dev/null 2>&1 && ! cmp -s "$_f" "$_dest"; then
            rm -f "$_dest"
            fix_abort_item "백업 검증 실패(원본과 내용이 다름): $_f"
        fi
    else
        : > "$_dest.WAS_ABSENT" 2>/dev/null || fix_abort_item "백업 기록 실패: $_f"
    fi
}

# fix_backup_owner <경로> — 소유자·권한만 바꾸는 조치용 백업. 내용을 복사하지 않고 숫자 uid:gid 와 권한만
# <백업>.OWNMETA 에 남긴다(심볼릭 링크는 링크 자체 기준). fix_backup 의 cp -p 사본은 원래 소유자를 그대로 가져
# U-15(소유자 없는 파일) 조치의 재검증 find 가 백업 폴더의 사본을 다시 찾아 항상 VULN → 원복되었다.
fix_backup_owner() {
    _f=$1
    _rel=$(printf '%s' "$_f" | sed 's#^/##')
    _dest="$FIX_BACKUP_DIR/$FIX_CODE/$_rel"
    if [ -e "$_dest" ] || [ -e "$_dest.OWNMETA" ] || [ -e "$_dest.DIRMETA" ] || [ -e "$_dest.WAS_ABSENT" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$_dest")" 2>/dev/null || fix_abort_item "백업 디렉터리를 만들 수 없음: $(dirname "$_dest")"
    _owner=$(stat -c '%u:%g' "$_f" 2>/dev/null)
    _perm=$(stat -c '%a' "$_f" 2>/dev/null)
    [ -n "$_owner" ] && [ -n "$_perm" ] || fix_abort_item "소유자/권한을 기록할 수 없음: $_f"
    printf '%s\n%s\n' "$_owner" "$_perm" > "$_dest.OWNMETA" 2>/dev/null || fix_abort_item "백업 기록 실패: $_f"
}

# fix_backup_remove_path <경로> — 파일/디렉터리를 완전히 삭제하기 전에 내용 전체를 tar로
# 보존한다. fix_backup() 의 디렉터리 처리(소유자/권한 메타데이터만 저장)와 달리, 이 함수는
# "삭제 자체가 조치"인 항목(WEB-07 기본 샘플/매뉴얼 디렉터리 제거 등) 전용으로 내용 전체를
# 백업해 원복 시 삭제 이전 상태로 완전히 복원할 수 있게 한다. tar 가 실패하면 삭제하지 않는다
# (예전에는 tar 실패를 무시하고 rm -rf 해 원본이 영구 소실될 수 있었다).
fix_backup_remove_path() {
    _f=$1
    if [ ! -e "$_f" ] && [ ! -L "$_f" ]; then
        return 0
    fi
    _rel=$(printf '%s' "$_f" | sed 's#^/##')
    _dest="$FIX_BACKUP_DIR/$FIX_CODE/$_rel"
    mkdir -p "$(dirname "$_dest")" 2>/dev/null || fix_abort_item "백업 디렉터리를 만들 수 없음: $(dirname "$_dest")"
    _parent=$(dirname "$_f")
    _base=$(basename "$_f")
    if ! (cd "$_parent" && tar czf "$_dest.TARBALL.tgz" "$_base") 2>/dev/null || ! tar tzf "$_dest.TARBALL.tgz" >/dev/null 2>&1; then
        rm -f "$_dest.TARBALL.tgz"
        fix_abort_item "삭제 전 백업(tar) 실패 — 삭제하지 않음: $_f"
    fi
    rm -rf "$_f"
}

# ---- 설정 파일 편집 헬퍼 (운영 안전 기준 F2, 1.2.2) ------------------------------------
# fix_write_back <임시파일> <대상파일> — 편집 결과를 mv 대신 "내용만" 덮어써 원래 파일의
# inode·소유자·권한·SELinux 컨텍스트를 유지한다. mv 로 바꾸면 root:root/umask 권한의 새 파일이
# 되어 서비스 계정(tomcat 등)이 못 읽거나 SELinux 라벨이 바뀌어 다음 기동이 실패할 수 있다.
fix_write_back() {
    cat "$1" > "$2" && rm -f "$1"
}

# apache_options_disable <파일> <옵션> — Options 지시어에서 옵션(Indexes/FollowSymLinks/Includes)을
# 끈다. Apache 2.4 는 한 Options 줄에 +/- 가 붙은 옵션과 안 붙은 옵션을 섞으면 문법 오류("Either all
# Options must start with + or -, or no Option may")로 기동에 실패한다 - 예전 조치는 "Options Indexes
# FollowSymLinks" 를 "Options -Indexes FollowSymLinks" 로 바꿔 다음 재시작 때 Apache 가 죽었다.
#   +/- 표기가 없는 줄 → 해당 옵션을 지운다(남는 게 없으면 Options None)
#   +/- 표기가 있는 줄 → 옵션(또는 +옵션)을 지우고 끝에 -옵션 을 붙인다(상위에서 상속된 값까지 끔)
# 1.3.3(F-R5): All(= Indexes Includes FollowSymLinks ExecCGI, MultiViews 제외)은 끌 옵션을 뺀 나머지로 풀어 쓰고,
# Includes 를 끌 때는 IncludesNOEXEC 도 지운다(진단 web_apache_option_hits 와 같은 기준). 예전에는 둘 다 몰라
# WEB-04/12/19 조치가 아무것도 바꾸지 못하고 재검증 VULN → 원복으로 끝났다.
# 바뀐 게 있으면 0, 없으면 1 을 반환한다. 파일 내용만 덮어써 심볼릭 링크(Debian sites-enabled)를 유지한다.
apache_options_disable() {
    _ao_f=$1; _ao_tok=$2
    awk -v tok="$_ao_tok" '
        BEGIN { changed = 0; ltok = tolower(tok); nall = split("Indexes Includes FollowSymLinks ExecCGI", all, " ") }
        function add(t, key) { if (!(key in seen)) { seen[key] = 1; out = out " " t } }
        {
            line = $0
            cr = ""; if (line ~ /\r$/) { cr = "\r"; sub(/\r$/, "", line) }
            lead = line; sub(/[^ \t].*$/, "", lead)
            body = line; sub(/^[ \t]+/, "", body)
            n = split(body, a, /[ \t]+/)
            if (n >= 1 && tolower(a[1]) == "options") {
                signed = 0
                for (i = 2; i <= n; i++) if (a[i] ~ /^[+-]/) signed = 1
                out = ""; hit = 0; split("", seen)
                for (i = 2; i <= n; i++) {
                    t = a[i]
                    if (t == "") continue
                    s = substr(t, 1, 1); w = tolower(t)
                    if (s == "+" || s == "-") w = substr(w, 2); else s = ""
                    if (s == "-") { add(t, "-" w); continue }
                    if (w == "all") {
                        hit = 1
                        for (k = 1; k <= nall; k++)
                            if (tolower(all[k]) != ltok) add((signed ? "+" : "") all[k], tolower(all[k]))
                        continue
                    }
                    if (w == ltok || (ltok == "includes" && w == "includesnoexec")) { hit = 1; continue }
                    add(t, w)
                }
                if (hit) {
                    if (signed) add("-" tok, "-" ltok)
                    if (out == "") out = " None"
                    line = lead a[1] out
                    changed = 1
                }
            }
            print line cr
        }
        END { exit(changed ? 0 : 1) }
    ' "$_ao_f" > "$_ao_f.kisa_tmp"
    _ao_rc=$?
    if [ "$_ao_rc" -eq 0 ]; then fix_write_back "$_ao_f.kisa_tmp" "$_ao_f"; else rm -f "$_ao_f.kisa_tmp"; fi
    return "$_ao_rc"
}

# apache_options_enabled <파일> <옵션> — 주석이 아닌 Options 줄에 옵션이 켜져(무표기·+옵션·All, Includes 는
# IncludesNOEXEC 포함) 있으면 0. 진단의 web_apache_option_hits 와 같은 기준(1.3.3, F-R5).
apache_options_enabled() {
    [ -n "$(web_apache_option_hits "$2" "$1")" ]
}

# web_sed_inplace <파일> <sed 인자...> — sed -i 대신 쓴다. sed -i 는 새 파일을 만들어 바꿔치기하므로 Debian 의
# sites-enabled/mods-enabled·conf-enabled 심볼릭 링크를 일반 파일로 바꿔 버리고(링크 대상은 그대로 남아
# 원복해도 링크가 돌아오지 않음 - fix_safety 실기로 발견) 소유자·SELinux 라벨도 바뀔 수 있다. 결과를
# fix_write_back 으로 내용만 덮어쓴다. sed 실패 시 원본을 건드리지 않고 1.
web_sed_inplace() {
    _wsi_f=$1; shift
    if sed "$@" "$_wsi_f" > "$_wsi_f.kisa_tmp" 2>/dev/null; then
        fix_write_back "$_wsi_f.kisa_tmp" "$_wsi_f"
    else
        rm -f "$_wsi_f.kisa_tmp"; return 1
    fi
}

# nginx_http_insert <파일> <지시어 줄> — 첫 "http {" 블록 바로 안쪽에 지시어를 넣는다. server_tokens /
# error_page / disable_symlinks 는 http·server·location 컨텍스트에서만 허용되는데, 예전 조치는 파일
# 맨 앞(1i)이나 맨 끝(main 컨텍스트)에 넣어 "directive is not allowed here" 로 다음 reload/재시작이
# 실패했다. http 블록을 찾지 못하면 아무것도 바꾸지 않고 1 을 반환한다(수동 조치 안내).
nginx_http_insert() {
    _ni_f=$1; _ni_line=$2
    grep -qE '^[[:space:]]*http[[:space:]]*\{' "$_ni_f" 2>/dev/null || return 1
    awk -v ins="$_ni_line" '
        !done && /^[ \t]*http[ \t]*\{/ { print; print "    # KISA 조치"; print "    " ins; done = 1; next }
        { print }
    ' "$_ni_f" > "$_ni_f.kisa_tmp" && fix_write_back "$_ni_f.kisa_tmp" "$_ni_f"
}

# web_config_test <apache|nginx> — 설정 문법 검사. 0=통과, 1=실패(WEB_CONFIG_TEST_OUT 에 출력),
# 2=검사 도구 없음. 실행 중인 서버에는 영향이 없다(설정 파일만 파싱).
web_config_test() {
    WEB_CONFIG_TEST_OUT=""
    case "$1" in
        apache)
            for _t in apachectl apache2ctl httpd; do
                command -v "$_t" >/dev/null 2>&1 || continue
                WEB_CONFIG_TEST_OUT=$("$_t" -t 2>&1) && return 0
                return 1
            done
            return 2 ;;
        nginx)
            command -v nginx >/dev/null 2>&1 || return 2
            WEB_CONFIG_TEST_OUT=$(nginx -t 2>&1) && return 0
            return 1 ;;
    esac
    return 2
}

# sshd_global_lines [설정파일] — sshd 가 전역(Match 블록 밖)으로 읽는 설정 줄을 "읽는 순서대로"
# 출력한다. Include 를 펼치고(상대경로는 /etc/ssh 기준), 각 파일에서 Match 이후는 제외한다.
# sshd 는 같은 키워드가 여러 번 나오면 **처음 값**을 쓴다(sshd_config(5)) - 마지막 값을 보면
# sshd_config.d 드롭인에서 먼저 지정된 값을 놓쳐 오판한다.
_sshd_filter_global() {
    awk '{ sub(/^[ \t]+/, ""); if ($0 == "" || substr($0, 1, 1) == "#") next
           k = tolower($1); if (k == "match") exit
           if (k == "include") { $1 = ""; print "@@INCLUDE" $0; next }
           print }' "$1" 2>/dev/null
}
sshd_global_lines() {
    _sg_cfg=${1:-/etc/ssh/sshd_config}
    [ -f "$_sg_cfg" ] || return 0
    _sshd_filter_global "$_sg_cfg" | while IFS= read -r _sg_l; do
        case "$_sg_l" in
            @@INCLUDE*)
                set -f
                # shellcheck disable=SC2086
                set -- ${_sg_l#@@INCLUDE}
                set +f
                for _sg_p in "$@"; do
                    case "$_sg_p" in /*) : ;; *) _sg_p="/etc/ssh/$_sg_p" ;; esac
                    # shellcheck disable=SC2086
                    for _sg_inc in $_sg_p; do
                        [ -f "$_sg_inc" ] && _sshd_filter_global "$_sg_inc" | grep -v '^@@INCLUDE'
                    done
                done ;;
            *) printf '%s\n' "$_sg_l" ;;
        esac
    done
}

# sshd_effective_value <키워드> — 실제로 적용되는 전역 값을 SSHD_VALUE 에, 근거를 SSHD_VALUE_SOURCE 에
# 담는다($(...) 로 부르면 서브셸이라 근거 변수가 전달되지 않으므로 출력 대신 변수로 돌려준다).
# sshd -T(유효 설정 출력)가 되면 그 값을, 안 되면(권한 부족·/run/sshd 없음 등) 파일 분석 첫 값을 쓴다.
sshd_effective_value() {
    _se_k=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    SSHD_VALUE=""
    if command -v sshd >/dev/null 2>&1; then
        SSHD_VALUE=$(run_to 15 sshd -T 2>/dev/null | awk -v k="$_se_k" '$1 == k { print $2; exit }')
        if [ -n "$SSHD_VALUE" ]; then SSHD_VALUE_SOURCE="sshd -T(실제 적용 값)"; return 0; fi
    fi
    SSHD_VALUE_SOURCE="설정 파일 분석(Include 반영, 처음 나온 값 우선)"
    SSHD_VALUE=$(sshd_global_lines | awk -v k="$_se_k" 'tolower($1) == k { print $2; exit }')
}

# sshd_match_overrides <키워드> — Match 블록 안에서 키워드를 지정한 줄(파일:내용). 전역은 no 여도
# 특정 사용자/주소에 예외를 둔 경우를 드러내기 위함.
sshd_match_overrides() {
    _so_k=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    for _so_f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
        [ -f "$_so_f" ] || continue
        awk -v k="$_so_k" -v f="$_so_f" '{ s = $0; sub(/^[ \t]+/, "", s); if (s == "" || substr(s, 1, 1) == "#") next
            split(s, a, /[ \t]+/); if (tolower(a[1]) == "match") m = 1
            else if (m && tolower(a[1]) == k) print f ": " s }' "$_so_f"
    done
}

# ---- DB 재기동 조치 헬퍼 (운영 안전 기준 F2, 1.3.0) ----------------------------------------------
# 정적 파라미터 조치(mysql D-07, postgres D-03/D-26)는 재기동이 필요하다. 예전에는 재기동 명령의 성공만 보고
# DB 가 실제로 떴는지 확인하지 않았고, 기동에 실패해도 설정을 되돌리지 않아 DB 가 내려간 채로 남을 수 있었다.

# db_wait_alive <초> — DBMS_ENGINE 에 접속될 때까지 최대 N초 기다린다(0=접속 확인, 1=시간 초과)
db_wait_alive() {
    _wa=0
    while [ "$_wa" -lt "$1" ]; do
        case "${DBMS_ENGINE:-}" in
            mysql) mysql_query "SELECT 1;" >/dev/null 2>&1 && return 0 ;;
            postgres) psql_query "SELECT 1;" >/dev/null 2>&1 && return 0 ;;
            oracle) oracle_query "SELECT 1 FROM dual;" >/dev/null 2>&1 && return 0 ;;
            *) return 1 ;;
        esac
        sleep 2; _wa=$((_wa + 2))
    done
    return 1
}

# db_restart_server — 지금 실행 중인 DB 서비스만 재기동한다. 0=재기동 명령 성공, 1=실패, 2=재기동 수단 없음
# (원격 실행 등). 예전처럼 실행 중이 아닌 유닛 이름까지 차례로 restart 하거나 systemd 밖에서 mysqld_safe 로
# 띄우지 않는다.
db_restart_server() {
    case "${DBMS_ENGINE:-}" in
        mysql) _units="mysqld mysql mariadb" ;;
        postgres) _units="postgresql postgresql-17 postgresql-16 postgresql-15 postgresql-14 postgresql-13 postgresql-12" ;;
        *) return 2 ;;
    esac
    if command -v systemctl >/dev/null 2>&1; then
        for _u in $_units; do
            systemctl is-active --quiet "$_u" 2>/dev/null || continue
            systemctl restart "$_u" 2>/dev/null && return 0
            return 1
        done
    fi
    if [ "$DBMS_ENGINE" = "postgres" ] && command -v pg_ctlcluster >/dev/null 2>&1; then
        _cl=$(pg_lsclusters 2>/dev/null | awk 'NR > 1 && $4 == "online" { print $1, $2; exit }')
        # shellcheck disable=SC2086
        [ -n "$_cl" ] && { pg_ctlcluster $_cl restart 2>/dev/null && return 0; return 1; }
    fi
    if command -v service >/dev/null 2>&1; then
        for _u in $_units; do
            service "$_u" status >/dev/null 2>&1 || continue
            service "$_u" restart >/dev/null 2>&1 && return 0
            return 1
        done
    fi
    return 2
}

# db_restart_or_revert <설명> — 재기동 후 기동을 확인하고, 뜨지 않으면 이 항목의 백업(설정 파일)으로 되돌린 뒤
# 다시 기동한다. 결과는 DB_RESTART_RESULT 에: ok / no_method / reverted / down(되돌렸는데도 안 뜸 - 즉시 수동 조치)
db_restart_or_revert() {
    db_restart_server
    case $? in
        2) DB_RESTART_RESULT="no_method"; return 1 ;;
    esac
    if db_wait_alive 60; then DB_RESTART_RESULT="ok"; return 0; fi
    log_error "[$FIX_CODE] $1 후 DB 가 다시 뜨지 않습니다 - 설정을 되돌리고 다시 기동합니다."
    fix_rollback_item "$FIX_CODE"
    db_restart_server
    if db_wait_alive 60; then DB_RESTART_RESULT="reverted"; else DB_RESTART_RESULT="down"; fi
    return 1
}

# ---- Oracle 정적 파라미터 조치의 재기동·복구 (D-19/D-26, 1.3.1) --------------------------------------
# SPFILE 을 바꾼 뒤 SHUTDOWN/STARTUP 을 하는데, 새 값 때문에 기동에 실패하면 인스턴스가 내려간 채로 남고 SQL 로는
# 되돌릴 수 없다(SPFILE 은 인스턴스가 떠 있어야 ALTER SYSTEM 으로 바꿀 수 있음). 그래서:
#   oracle_pfile_backup <코드>  — 변경 "전" SPFILE 을 PFILE 로 떠 둔다(실패하면 조치하지 말 것)
#   oracle_restart_or_recover   — 재기동 후 기동을 확인하고, 안 뜨면 PFILE 로 기동해 SPFILE 을 원래대로 다시
#                                 만들고 재기동한다. 결과는 DB_RESTART_RESULT(ok/reverted/down)
# PFILE 은 oracle 계정이 쓸 수 있는 $ORACLE_HOME/dbs 에 두고(백업 디렉터리는 root 700 이라 oracle 이 못 씀),
# 경로를 ORACLE_PFILE_BACKUP 에 담는다.
oracle_pfile_backup() {
    _oh=$(oracle_home)
    [ -n "$_oh" ] && [ -d "$_oh/dbs" ] || return 1
    ORACLE_PFILE_BACKUP="$_oh/dbs/kisa_${1}_$(date '+%Y%m%d%H%M%S').ora"
    oracle_query "CREATE PFILE='$ORACLE_PFILE_BACKUP' FROM SPFILE;" >/dev/null || return 1
    [ -s "$ORACLE_PFILE_BACKUP" ] || return 1
    # 백업 디렉터리에도 사본을 남긴다(원본 SPFILE 내용 증적)
    mkdir -p "$FIX_BACKUP_DIR/$FIX_CODE/_oracle" 2>/dev/null && cp -p "$ORACLE_PFILE_BACKUP" "$FIX_BACKUP_DIR/$FIX_CODE/_oracle/" 2>/dev/null
    return 0
}

oracle_restart_or_recover() {
    # 재기동은 도중에 끊으면 DB 가 내려간 채로 남으므로 시간 제한을 걸지 않는다
    DB_CMD_TIMEOUT=0 oracle_query "SHUTDOWN IMMEDIATE;
STARTUP;" >/dev/null 2>&1
    if db_wait_alive 120; then DB_RESTART_RESULT="ok"; return 0; fi
    log_error "[$FIX_CODE] 재기동 후 Oracle 이 열리지 않습니다 - 변경 전 PFILE 로 기동해 SPFILE 을 되돌립니다($ORACLE_PFILE_BACKUP)."
    DB_CMD_TIMEOUT=0 oracle_query "SHUTDOWN ABORT;" >/dev/null 2>&1
    DB_CMD_TIMEOUT=0 oracle_query "STARTUP PFILE='$ORACLE_PFILE_BACKUP';" >/dev/null 2>&1
    if db_wait_alive 120 \
       && DB_CMD_TIMEOUT=0 oracle_query "CREATE SPFILE FROM PFILE='$ORACLE_PFILE_BACKUP';" >/dev/null 2>&1; then
        # PFILE 로 떠 있는 상태 - 복원한 SPFILE 로 다시 기동해 이후 재기동에도 원래 값이 쓰이게 한다
        DB_CMD_TIMEOUT=0 oracle_query "SHUTDOWN IMMEDIATE;
STARTUP;" >/dev/null 2>&1
    fi
    if db_wait_alive 120; then DB_RESTART_RESULT="reverted"; else DB_RESTART_RESULT="down"; fi
    return 1
}

# ---- 비밀번호 변경 조치 헬퍼 (1.3.0, 사용자 결정: 무작위 생성 폐지 → 사전 승인 + 직접 입력) ----------
# 예전 조치(mysql D-01/D-08, postgres D-01, WEB-02)는 무작위 비밀번호를 만들어 아무 데도 기록하지 않아
# 앱·관리 접속이 끊기고 아무도 새 값을 몰랐다. 이제 계정마다 승인을 받고 운영자가 새 비밀번호를
# 터미널에서 직접 입력한다. 비대화형이면 아무것도 바꾸지 않는다. 비밀번호는 인자·로그·백업에 남기지 않는다.

# fix_tty_available — 제어 터미널을 실제로 열 수 있으면 0(/dev/tty 파일이 있어도 cron/docker 에선 열기 실패)
fix_tty_available() {
    ( : < /dev/tty ) 2>/dev/null
}

# fix_confirm_tty <질문> — 터미널에서 y/N(파이프 입력으로는 승인 불가). 비대화형이면 1.
fix_confirm_tty() {
    fix_tty_available || return 1
    printf '%s [y/N] ' "$1" > /dev/tty
    _ct=""
    IFS= read -r _ct < /dev/tty || _ct=""
    case "$_ct" in y|Y) return 0 ;; esac
    return 1
}

# fix_read_new_password <대상 설명> — 새 비밀번호를 화면 표시 없이 2회 입력받아 FIX_NEW_PASSWORD 에 담는다.
# 8자 미만·불일치는 다시 묻고(최대 3회), 끝내 실패하거나 비대화형이면 1(변경하지 않음).
# 호출부는 사용 직후 FIX_NEW_PASSWORD="" 로 지운다.
fix_read_new_password() {
    FIX_NEW_PASSWORD=""
    fix_tty_available || return 1
    _rp_try=0
    while [ "$_rp_try" -lt 3 ]; do
        _rp_try=$((_rp_try + 1))
        printf '  %s 새 비밀번호(화면에 표시되지 않음, 8자 이상): ' "$1" > /dev/tty
        stty -echo < /dev/tty 2>/dev/null
        _rp1=""; IFS= read -r _rp1 < /dev/tty || _rp1=""
        stty echo < /dev/tty 2>/dev/null; printf '\n' > /dev/tty
        printf '  한 번 더 입력: ' > /dev/tty
        stty -echo < /dev/tty 2>/dev/null
        _rp2=""; IFS= read -r _rp2 < /dev/tty || _rp2=""
        stty echo < /dev/tty 2>/dev/null; printf '\n' > /dev/tty
        if [ "${#_rp1}" -lt 8 ]; then
            printf '  8자 이상이어야 합니다.\n' > /dev/tty
        elif [ "$_rp1" != "$_rp2" ]; then
            printf '  두 입력이 다릅니다.\n' > /dev/tty
        else
            FIX_NEW_PASSWORD=$_rp1; _rp1=""; _rp2=""
            return 0
        fi
    done
    _rp1=""; _rp2=""
    printf '  비밀번호를 설정하지 않고 건너뜁니다.\n' > /dev/tty
    return 1
}

# sql_quote_mysql / sql_quote_pg <값> — SQL 문자열 리터럴('...') 안에 넣을 수 있게 이스케이프한다.
# 운영자가 입력한 비밀번호에 ' 나 \ 가 있어도 SQL 이 깨지거나 다른 문장이 실행되지 않게 한다.
sql_quote_mysql() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}
sql_quote_pg() {
    printf '%s' "$1" | sed -e "s/'/''/g"
}

# db_exec_stdin <mysql|postgres> <sql> — 비밀번호가 들어간 SQL 을 명령 인자(-e/-c)가 아니라 표준입력으로
# 보낸다. 인자로 넘기면 실행되는 동안 ps 로 다른 사용자에게도 보인다.
db_exec_stdin() {
    _db_conn_blocked && return 1
    case "$1" in
        mysql)
            (
                [ -n "${DB_PASSWORD:-}" ] && export MYSQL_PWD="$DB_PASSWORD"
                # shellcheck disable=SC2046
                printf '%s\n' "$2" | _db_run mysql $(mysql_args)
            ) 2>"${DB_ERR_FILE:-/dev/null}" ;;
        postgres)
            (
                [ -n "${DB_PASSWORD:-}" ] && export PGPASSWORD="$DB_PASSWORD"
                export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
                # shellcheck disable=SC2046
                printf '%s\n' "$2" | _db_run psql $(psql_args) -v ON_ERROR_STOP=1
            ) 2>"${DB_ERR_FILE:-/dev/null}" ;;
        *) return 1 ;;
    esac
}

# ---- fix 진입점 공통 가드 (운영 안전 기준 F1·F6, 1.2.2) ------------------------------
# fix_require_root — 적용/원복을 root 로만 허용한다. 권한이 모자라면 일부 파일만 바뀌고
# 원복(chown/cp -p)도 실패해 "반쯤 바뀐" 상태가 남기 때문이다. 08_dbms 는 Oracle OS 인증
# (oracle 계정/dba 그룹)으로 실행해야 해 이 가드를 쓰지 않는다.
fix_require_root() {
    [ "$(id -u 2>/dev/null)" = "0" ] && return 0
    log_error "조치 적용/원복은 root 권한이 필요합니다(권한 부족으로 일부만 바뀌거나 원복이 실패하는 것을 막기 위해 중단, 변경 없음)."
    exit 2
}

# fix_lock_acquire <out_base> <category_num> — 같은 카테고리의 조치가 동시에 돌면 서로의 백업을
# 덮어쓰고 같은 파일을 번갈아 고치므로 원자적 mkdir 잠금으로 막는다. 종료 시 fix_lock_release.
fix_lock_acquire() {
    ( umask 077; mkdir -p "$1" ) 2>/dev/null
    FIX_LOCK_DIR="$1/.fix_$2.lock"
    if ! mkdir "$FIX_LOCK_DIR" 2>/dev/null; then
        _lpid=$(cat "$FIX_LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$_lpid" ] && kill -0 "$_lpid" 2>/dev/null; then
            log_error "다른 조치(fix) 실행이 진행 중입니다(PID $_lpid). 끝난 뒤 다시 실행하세요. (잠금: $FIX_LOCK_DIR)"
            FIX_LOCK_DIR=""
            exit 2
        fi
        log_warn "이전 실행이 남긴 잠금을 정리합니다(PID ${_lpid:-알 수 없음}, 실행 중 아님)."
        rm -rf "$FIX_LOCK_DIR"
        mkdir "$FIX_LOCK_DIR" 2>/dev/null || { log_error "잠금을 만들 수 없습니다: $FIX_LOCK_DIR"; FIX_LOCK_DIR=""; exit 2; }
    fi
    echo $$ > "$FIX_LOCK_DIR/pid"
}

fix_lock_release() {
    [ -n "${FIX_LOCK_DIR:-}" ] && rm -rf "$FIX_LOCK_DIR"
    FIX_LOCK_DIR=""
}

# fix_confirm_plan <코드...> — --apply 시 실제로 바뀔 항목을 먼저 모두 보여주고 1회 확인받는다.
# auto 등급은 항목별 확인 없이 적용되므로, 예전처럼 --apply 만 붙이면 경고 없이 auto 전체가
# 적용되던 문제를 막는다. --yes(YES=1)는 이 1회 확인만 생략한다(confirm 등급은 여전히 항목별 확인).
# 비대화형(터미널 없음)에서 --yes 없이 실행하면 아무것도 바꾸지 않고 끝낸다.
# fix_rollback_note <조치 파일> — 조치 파일 머리말의 "# 원복: ..." 표기. 없으면 빈 값(= 백업으로 원복 가능).
# 원복할 수 없거나 일부만 되돌아가는 조치를 적용 "전에" 알리기 위함(운영 안전 기준 F4).
fix_rollback_note() {
    [ -f "$1" ] && sed -n '1,12s/^# 원복: //p' "$1" | head -n1
}

fix_confirm_plan() {
    [ "${YES:-0}" -eq 1 ] && return 0
    echo "다음 항목을 실제로 변경합니다:"
    _n_auto=0
    for _c in "$@"; do
        _g=$(guide_field "$GUIDE_JSON" "$_c" "fix"); [ -z "$_g" ] && _g="manual"
        _t=$(guide_field "$GUIDE_JSON" "$_c" "title")
        _rb=$(fix_rollback_note "${FIX_FILE_DIR:-.}/$_c.sh")
        case "$_g" in
            auto) printf '  [auto]    %-8s %s  ← 개별 확인 없이 적용\n' "$_c" "$_t"; _n_auto=$((_n_auto + 1)) ;;
            confirm) printf '  [confirm] %-8s %s  ← 적용 직전 항목별로 다시 확인\n' "$_c" "$_t" ;;
        esac
        case "$_g" in auto|confirm) [ -n "$_rb" ] && printf '            └ 원복: %s\n' "$_rb" ;; esac
    done
    printf '위 목록대로 진행하시겠습니까? (auto %s건은 추가 확인 없이 적용됨) [y/N] ' "$_n_auto"
    _ans=""
    read -r _ans < /dev/tty 2>/dev/null || _ans=""
    case "$_ans" in
        y|Y) return 0 ;;
        *) echo; echo "중단 — 아무것도 변경하지 않았습니다. (비대화형 실행은 --yes 로 이 확인을 생략할 수 있음)"; exit 0 ;;
    esac
}

# fix_rollback_item <코드> — 해당 항목에서 백업한 SQL·파일·서비스 상태를 원상 복구한다.
# 실패한 원복은 FIX_ROLLBACK_FAILS 에 누적한다(운영 안전 기준 F4) - 예전에는 모든 오류를 삼키고 항상
# "원복 완료"로 표시해, 실제로 되돌아가지 않은 변경을 운영자가 알 수 없었다. 파이프(| while)는 서브셸이라
# 실패 집계가 전달되지 않으므로 here-doc 반복문을 쓴다.
FIX_ROLLBACK_FAILS=""
_rb_fail() { FIX_ROLLBACK_FAILS="$FIX_ROLLBACK_FAILS
[$_code] $1"; }
fix_rollback_item() {
    _code=$1
    _dir="$FIX_BACKUP_DIR/$_code"
    [ -d "$_dir" ] || return 0

    # DBMS SQL 원복은 파일 원복과 메커니즘이 완전히 달라(DB_* 접속 환경변수를 이용해 실제 SQL을
    # 재실행) 별도로 먼저 처리한다. 같은 항목 안에서 여러 SQL을 순서대로 큐에 넣었을 수 있으므로
    # (예: 계정 3개를 순서대로 잠금) 적용 역순(번호 내림차순)으로 실행한다. "--" 로 시작하는 큐는
    # 원복 SQL 이 없다는 기록이라 실행하지 않고 원복 불가로 보고한다.
    _sqldir="$_dir/dbsql"
    if [ -d "$_sqldir" ]; then
        for _sqlfile in $(ls "$_sqldir" 2>/dev/null | sort -r); do
            _sql=$(cat "$_sqldir/$_sqlfile")
            case "$_sql" in
                --*) _rb_fail "SQL 원복 불가(기록만 있음): $(printf '%s' "$_sql" | head -n1)"; continue ;;
            esac
            _rc=0
            case "$_sqlfile" in
                *.mysql.sql) mysql_query "$_sql" >/dev/null 2>&1 || _rc=1 ;;
                *.postgres.sql) psql_query "$_sql" >/dev/null 2>&1 || _rc=1 ;;
                *.oracle.sql) oracle_query "$_sql" >/dev/null 2>&1 || _rc=1 ;;
            esac
            [ "$_rc" -eq 0 ] || _rb_fail "SQL 원복 실패: $(printf '%s' "$_sql" | head -n1)"
        done
    fi

    _baklist=$(find "$_dir" -type f 2>/dev/null)
    while IFS= read -r _bak; do
        [ -z "$_bak" ] && continue
        case "$_bak" in
            */dbsql/*|*/_services/*)
                : # 따로 처리
                ;;
            *.WAS_ABSENT)
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.WAS_ABSENT}"
                if [ -d "$_orig" ]; then rmdir "$_orig" 2>/dev/null || _rb_fail "조치가 만든 디렉터리를 지우지 못함(비어 있지 않음): $_orig"
                else rm -f "$_orig" || _rb_fail "조치가 만든 파일 삭제 실패: $_orig"; fi
                ;;
            *.OWNMETA)
                # fix_backup_owner 가 남긴 소유자·권한(파일·심볼릭 링크 공용). 링크는 링크 자체 소유자만 되돌린다.
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.OWNMETA}"
                if [ -e "$_orig" ] || [ -L "$_orig" ]; then
                    _owner=$(sed -n '1p' "$_bak")
                    _perm=$(sed -n '2p' "$_bak")
                    if ! chown -h "$_owner" "$_orig" 2>/dev/null || { [ ! -L "$_orig" ] && ! chmod "$_perm" "$_orig" 2>/dev/null; }; then
                        _rb_fail "소유자/권한 원복 실패: $_orig"
                    fi
                fi
                ;;
            *.DIRMETA)
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.DIRMETA}"
                if [ -d "$_orig" ]; then
                    _owner=$(sed -n '1p' "$_bak")
                    _perm=$(sed -n '2p' "$_bak")
                    chown "$_owner" "$_orig" 2>/dev/null && chmod "$_perm" "$_orig" 2>/dev/null || _rb_fail "디렉터리 소유자/권한 원복 실패: $_orig"
                fi
                ;;
            *.TARBALL.tgz)
                _orig="/${_bak#"$_dir"/}"
                _orig="${_orig%.TARBALL.tgz}"
                _origparent=$(dirname "$_orig")
                mkdir -p "$_origparent"
                (cd "$_origparent" 2>/dev/null && tar xzf "$_bak") || _rb_fail "삭제된 경로 복원 실패: $_orig"
                ;;
            *)
                _orig="/${_bak#"$_dir"/}"
                cp -p "$_bak" "$_orig" 2>/dev/null || _rb_fail "파일 원복 실패: $_orig"
                ;;
        esac
    done <<EOF
$_baklist
EOF

    # 서비스 상태는 설정 파일을 되돌린 뒤 마지막에 되살린다(fix_service_disable 가 기록)
    if [ -d "$_dir/_services" ] && command -v systemctl >/dev/null 2>&1; then
        for _sf in "$_dir/_services"/*; do
            [ -f "$_sf" ] || continue
            _unit=$(basename "$_sf")
            _was_enabled=$(sed -n '1p' "$_sf"); _was_active=$(sed -n '2p' "$_sf")
            [ "$_was_enabled" = "enabled" ] && { systemctl enable "$_unit" >/dev/null 2>&1 || _rb_fail "서비스 enable 원복 실패: $_unit"; }
            [ "$_was_active" = "active" ] && { systemctl start "$_unit" >/dev/null 2>&1 || _rb_fail "서비스 기동 원복 실패: $_unit"; }
        done
    fi
}

# fix_set_owner_perm <파일> <소유자> <권한> — check_owner_perm 과 짝을 이루는 조치 헬퍼.
# 소유자는 인자로 받은 값 그대로(여러 후보 중 첫 번째를 호출부에서 선택해 전달), 권한은
# 정확히 그 값으로 설정한다(check_owner_perm 은 "이하"를 허용하지만 조치는 가이드 권고값으로 고정).
fix_set_owner_perm() {
    _f=$1; _owner=$2; _perm=$3
    if [ ! -e "$_f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$_f 파일이 존재하지 않음"; FIX_EVIDENCE=""
        return 1
    fi
    fix_backup "$_f"
    chown "$_owner" "$_f" 2>/dev/null
    chmod "$_perm" "$_f" 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$_f 소유자를 $_owner, 권한을 $_perm 로 설정함"
    FIX_EVIDENCE="$(ls -l "$_f" 2>/dev/null)"
}

# fix_service_disable <systemd 유닛...> — check_service_disabled 와 짝을 이루는 조치 헬퍼.
# 실행 중인 서비스를 정지(stop)하고 비활성화(disable)한다. 유닛이 하나라도 처리되면 0을 반환.
fix_service_disable() {
    _ok=0
    if command -v systemctl >/dev/null 2>&1; then
        for _u in "$@"; do
            systemctl list-unit-files "$_u" >/dev/null 2>&1 || continue
            # 원복용으로 원래 상태(enabled/active)를 기록한다 - 예전에는 기록하지 않아 원복해도 서비스가 다시
            # 켜지지 않았다. 같은 항목에서 이미 기록했으면 첫 기록(조치 전 상태)을 유지한다.
            _sd="$FIX_BACKUP_DIR/$FIX_CODE/_services"
            if [ ! -f "$_sd/$_u" ]; then
                mkdir -p "$_sd" 2>/dev/null || fix_abort_item "서비스 상태 백업 디렉터리 생성 실패: $_sd"
                { systemctl is-enabled "$_u" 2>/dev/null | head -n1; systemctl is-active "$_u" 2>/dev/null | head -n1; } > "$_sd/$_u" \
                    || fix_abort_item "서비스 상태 백업 실패: $_u"
            fi
            systemctl stop "$_u" 2>/dev/null
            systemctl disable "$_u" 2>/dev/null && _ok=1
        done
    fi
    [ "$_ok" -eq 1 ] && return 0 || return 1
}

# fix_xinetd_disable <xinetd.d 파일...> — "disable = no" 로 명시된 서비스를 "disable = yes" 로
# 강제한다(값이 아예 없는 파일은 배포판 기본값을 신뢰해 건드리지 않는다). 하나라도 바꾸면 xinetd를
# reload(가능한 경우)해 즉시 반영하고 0을 반환한다 — 일부 항목(U-38 등)은 check가 listening 포트
# 상태(ss/netstat)를 직접 확인하므로, 설정 파일만 고치고 reload 하지 않으면 재검증이 통과하지 않는다.
# sshd 등 관리 세션에 영향을 줄 수 있는 서비스는 절대 자동 재시작하지 않는다는 원칙과 달리,
# xinetd reload는 관리자 세션에 영향이 없어 안전하다.
fix_xinetd_disable() {
    _changed=0
    for _f in "$@"; do
        [ -f "$_f" ] || continue
        grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' "$_f" || continue
        fix_backup "$_f"
        sed -i -E 's/^([[:space:]]*disable[[:space:]]*=[[:space:]]*)no/\1yes/' "$_f"
        _changed=1
    done
    if [ "$_changed" -eq 1 ]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl try-reload-or-restart xinetd 2>/dev/null
        elif command -v service >/dev/null 2>&1; then
            service xinetd reload 2>/dev/null
        fi
        return 0
    fi
    return 1
}

# ---- DBMS 전용: SQL 기반 원복 (08_dbms) -------------------------------------
# DB 상태는 파일이 아니라 SQL 실행 결과이므로, 파일 기반 fix_backup 과 달리 "원복용 SQL 문
# 자체"를 백업 위치에 기록해 두고 fix_rollback_item 이 그 SQL 을 다시 실행하는 방식으로
# 원복한다. fixes/<engine>/D-xx.sh 는 실제 변경 전에 반드시 이 함수로 원복 SQL 을 큐에 넣는다.
fix_db_queue_rollback() {
    _engine=$1; _sql=$2
    _dir="$FIX_BACKUP_DIR/$FIX_CODE/dbsql"
    mkdir -p "$_dir"
    _n=1
    while [ -f "$_dir/$(printf '%04d' "$_n").$_engine.sql" ]; do _n=$((_n + 1)); done
    printf '%s\n' "$_sql" > "$_dir/$(printf '%04d' "$_n").$_engine.sql"
}

# fix_rollback_all <fix-run-dir> — fix.sh --rollback 용: 해당 실행의 백업 전체를 원복한다.
# 여러 항목이 같은 파일을 순차적으로 수정한 경우, 원복은 적용의 역순(나중에 바뀐 항목부터)으로
# 처리해야 최종 상태가 "전부 적용 전"으로 정확히 돌아간다. 정순으로 처리하면 뒤에 적용된 항목의
# 백업(이미 앞 항목의 변경이 반영된 상태의 스냅샷)이 마지막에 덮어써 앞 항목의 조치만 남는 버그가
# 있었다(Web WEB-04/08/16/22가 같은 httpd.conf 를 순차 수정하는 실기 테스트로 실제로 발견 —
# 코드가 U-01~U-67 처럼 전부 2자리 zero-padding 이라 사전식 역순 정렬이 곧 적용 역순과 같다).
fix_rollback_all() {
    _run_dir=$1
    _backup_dir="$_run_dir/backup"
    if [ ! -d "$_backup_dir" ]; then
        log_error "$_backup_dir 를 찾을 수 없습니다."
        return 1
    fi
    # 다른 호스트에서 만든 백업을 이 호스트에 덮어쓰는 사고 방지(폴더 이름 규칙: <host>_<카테고리>_fix_<시각>)
    _rb_host=$(basename "$_run_dir" | sed 's/_[0-9][0-9]_fix_.*$//')
    _this_host=$(hostname 2>/dev/null || echo unknown-host)
    if [ "$_rb_host" != "$_this_host" ]; then
        log_warn "이 백업은 다른 호스트($_rb_host)에서 만든 것으로 보입니다(현재: $_this_host)."
        fix_confirm_tty "그래도 이 호스트에 원복하시겠습니까?" || { echo "원복하지 않았습니다."; return 1; }
    fi
    # 조치 이후 경과 시간이 길면 그 사이의 정상적인 설정 변경까지 되돌리게 된다 - 알리고 진행한다
    log_warn "원복은 조치 직전 상태로 덮어씁니다. 조치 이후에 사람이 바꾼 설정이 있으면 함께 되돌아갑니다."
    _codes=""
    for _code_dir in "$_backup_dir"/*/; do
        [ -d "$_code_dir" ] || continue
        _codes="$_codes
$(basename "$_code_dir")"
    done
    _codes=$(printf '%s\n' "$_codes" | grep -v '^$' | sort -r)
    FIX_ROLLBACK_FAILS=""
    for _code in $_codes; do
        _before_fails=$FIX_ROLLBACK_FAILS
        FIX_BACKUP_DIR="$_backup_dir" fix_rollback_item "$_code"
        if [ "$_before_fails" = "$FIX_ROLLBACK_FAILS" ]; then echo "원복 완료: $_code"; else echo "원복 일부 실패: $_code"; fi
    done
    if [ -n "$FIX_ROLLBACK_FAILS" ]; then
        log_error "되돌리지 못한 항목이 있습니다 - 수동 확인 필요:$FIX_ROLLBACK_FAILS"
        return 1
    fi
}
