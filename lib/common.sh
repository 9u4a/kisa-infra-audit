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
# JSON 문자열은 raw TAB/CR 같은 제어문자를 이스케이프 없이 포함할 수 없다(JSON 스펙 위반).
# mysql/psql 의 배치(-B/-A) 출력은 컬럼을 TAB 으로 구분하므로, DBMS 증적(evidence)을 그대로
# 담으면 생성된 result.json 이 깨진다(Python json.loads 가 "Invalid control character" 로 거부하는
# 실제 버그를 08_dbms Docker 검증 중 발견). 이스케이프 전에 TAB/CR 을 먼저 정리한다.
json_escape() {
    printf '%s' "$1" | tr '\t\r' '  ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
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

# ---- 웹 엔진 자동 탐지 및 설정 경로 조회 (03_web 전용) -------------------------
# 여러 엔진이 동시에 설치되어 있을 수 있으므로 공백 구분 목록으로 반환한다.
detect_web_engines() {
    WEB_ENGINES=""
    { command -v httpd >/dev/null 2>&1 || command -v apache2 >/dev/null 2>&1 || \
      [ -x /usr/local/apache2/bin/httpd ]; } && WEB_ENGINES="$WEB_ENGINES apache"
    { command -v nginx >/dev/null 2>&1 || pgrep -x nginx >/dev/null 2>&1; } && \
      WEB_ENGINES="$WEB_ENGINES nginx"
    { [ -n "${CATALINA_HOME:-}" ] || pgrep -f catalina >/dev/null 2>&1 || \
      [ -x /usr/local/tomcat/bin/catalina.sh ]; } && WEB_ENGINES="$WEB_ENGINES tomcat"
    pgrep -f jeus >/dev/null 2>&1 && WEB_ENGINES="$WEB_ENGINES jeus"
    pgrep -x wsbtoc >/dev/null 2>&1 && WEB_ENGINES="$WEB_ENGINES webtob"
    WEB_ENGINES=$(printf '%s' "$WEB_ENGINES" | sed -E 's/^ //')
}

# apache_conf_path — 대표적인 설치 레이아웃(공식 도커/소스, Debian/Ubuntu, RHEL 계열) 순으로 탐색
apache_conf_path() {
    for p in /usr/local/apache2/conf/httpd.conf /etc/apache2/apache2.conf /etc/httpd/conf/httpd.conf; do
        [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

# apache_extra_confs — httpd.conf 가 "실제로" Include/IncludeOptional 하는 파일만 재귀적으로
# 찾아 반환한다. 공식 Docker 이미지 등은 conf/extra/ 안에 기본적으로 비활성(주석 처리된
# Include) 샘플 설정이 다수 들어있어, 디렉터리를 통째로 훑으면 실제로는 로드되지 않는 설정
# (예: httpd-dav.conf 의 "Dav On" 예시)을 활성 설정으로 오판하는 실제 버그가 있었다
# (03_web WEB-18 을 Docker 컨테이너로 검증하다 발견). 반드시 Include 체인을 따라간다.
_apache_resolve_includes() {
    _file=$1; _root=$2
    [ -f "$_file" ] || return 0
    grep -E '^[[:space:]]*Include(Optional)?[[:space:]]+' "$_file" 2>/dev/null | \
    sed -E 's/^[[:space:]]*Include(Optional)?[[:space:]]+"?([^"]*)"?[[:space:]]*$/\2/' | \
    while IFS= read -r _pat; do
        case "$_pat" in
            /*) _resolved="$_pat" ;;
            *) _resolved="$_root/$_pat" ;;
        esac
        for _f in $_resolved; do
            [ -f "$_f" ] || continue
            echo "$_f"
            _apache_resolve_includes "$_f" "$_root"
        done
    done
}

apache_extra_confs() {
    _main=$(apache_conf_path) || return 1
    _root=$(grep -E '^[[:space:]]*ServerRoot' "$_main" 2>/dev/null | head -n1 | \
            sed -E 's/^[[:space:]]*ServerRoot[[:space:]]+"?([^"]*)"?.*/\1/')
    [ -z "$_root" ] && _root=$(dirname "$(dirname "$_main")")
    _apache_resolve_includes "$_main" "$_root"
}

nginx_conf_path() {
    for p in /etc/nginx/nginx.conf /usr/local/nginx/conf/nginx.conf; do
        [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

# nginx_extra_confs — nginx.conf 가 "실제로" include 하는 파일만 재귀적으로 찾아 반환한다
# (Apache 와 동일한 이유로 디렉터리 전체를 훑지 않는다).
_nginx_resolve_includes() {
    _file=$1
    [ -f "$_file" ] || return 0
    grep -E '^[[:space:]]*include[[:space:]]+' "$_file" 2>/dev/null | \
    sed -E 's/^[[:space:]]*include[[:space:]]+"?([^";]*)"?[[:space:]]*;.*/\1/' | \
    while IFS= read -r _pat; do
        for _f in $_pat; do
            [ -f "$_f" ] || continue
            echo "$_f"
            _nginx_resolve_includes "$_f"
        done
    done
}

nginx_extra_confs() {
    _main=$(nginx_conf_path) || return 1
    _nginx_resolve_includes "$_main"
}

# tomcat_home — $CATALINA_HOME 우선, 없으면 대표 설치 경로 탐색
tomcat_home() {
    if [ -n "${CATALINA_HOME:-}" ] && [ -d "$CATALINA_HOME" ]; then
        echo "$CATALINA_HOME"; return 0
    fi
    for d in /usr/local/tomcat /opt/tomcat /usr/share/tomcat9 /usr/share/tomcat10 /var/lib/tomcat9; do
        [ -d "$d" ] && { echo "$d"; return 0; }
    done
    return 1
}

# ---- /proc 기반 프로세스 조회 (pgrep/ps 미설치 환경 대비) ---------------------
# 최소 구성 컨테이너 이미지(예: 공식 httpd/nginx Docker 이미지)는 procps 패키지가 없어
# ps/pgrep 자체가 없는 경우가 흔하다. /proc/*/comm, /proc/*/status 는 커널이 직접 제공하므로
# 항상 사용 가능하며, 이 방식이 더 이식성이 높다 (03_web WEB-09 구현 중 실제로 겪은 문제).
# proc_pids_by_comm <comm 이름> -> 일치하는 PID 목록(줄바꿈 구분)
proc_pids_by_comm() {
    _name=$1
    for _p in /proc/[0-9]*; do
        [ -r "$_p/comm" ] || continue
        _c=$(cat "$_p/comm" 2>/dev/null)
        [ "$_c" = "$_name" ] && echo "${_p#/proc/}"
    done
}

# proc_uid <pid> -> 실제 UID (숫자, root=0)
proc_uid() {
    awk '/^Uid:/{print $2; exit}' "/proc/$1/status" 2>/dev/null
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
    if [ -n "${DB_PASSWORD:-}" ]; then
        # shellcheck disable=SC2046
        MYSQL_PWD="$DB_PASSWORD" mysql $(mysql_args) -e "$1" 2>"${DB_ERR_FILE:-/dev/null}"
    else
        # shellcheck disable=SC2046
        mysql $(mysql_args) -e "$1" 2>"${DB_ERR_FILE:-/dev/null}"
    fi
}

mysql_config_path() {
    for _f in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf \
              /etc/mysql/mariadb.conf.d/50-server.cnf; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

# ---- DBMS 공통: PostgreSQL 연결/쿼리 ----------------------------------------
psql_args() {
    _a="-X -q -t -A --no-psqlrc"
    [ -n "${DB_HOST:-}" ] && _a="$_a -h $DB_HOST"
    [ -n "${DB_PORT:-}" ] && _a="$_a -p $DB_PORT"
    [ -n "${DB_USER:-}" ] && _a="$_a -U $DB_USER"
    _a="$_a -d ${DB_NAME:-postgres}"
    printf '%s' "$_a"
}

# psql_query <sql>  -- 결과를 |로 구분된 행으로 stdout 에 출력, 실패 시 0이 아닌 값 반환
psql_query() {
    if [ -n "${DB_PASSWORD:-}" ]; then
        # shellcheck disable=SC2046
        PGPASSWORD="$DB_PASSWORD" psql $(psql_args) -c "$1" 2>"${DB_ERR_FILE:-/dev/null}"
    else
        # shellcheck disable=SC2046
        psql $(psql_args) -c "$1" 2>"${DB_ERR_FILE:-/dev/null}"
    fi
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
