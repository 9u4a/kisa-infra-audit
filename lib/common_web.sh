# lib/common_web.sh — 03_web 웹 엔진 탐지·설정 경로 조회, XML 주석 제거·속성 파싱 헬퍼
# lib/common.sh 가 source 한다(직접 source 하지 말 것). 1.5.0 D3 에서 common.sh(2686줄)를 나눴다 - 함수는 모두
# common.sh 를 source 한 뒤 쓸 수 있고, 최상위 코드는 변수 할당뿐이라 파일 순서와 무관하다.
# shellcheck shell=sh

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

# _proc_conf_arg <comm 목록(공백)> <옵션> -> 그 이름으로 실행 중인 프로세스 명령행에서 <옵션> 다음 인자(첫 번째 것)를 출력.
# 실무 적용 검증 P-06: 운영 서버는 httpd -f /opt/.../httpd.conf, nginx -c /etc/nginx/site.conf 처럼 비표준 설정으로 띄우는
# 경우가 있다 - 예전에는 고정 경로만 봐 실제로 쓰지 않는(또는 다른) 파일로 판정했다. 절대 경로만 받아들인다.
_proc_conf_arg() {
    for _pca_c in $1; do
        for _pca_p in $(proc_pids_by_comm "$_pca_c"); do
            _pca_v=$(tr '\000' '\n' 2>/dev/null < "/proc/$_pca_p/cmdline" | awk -v o="$2" 'n { print; exit } $0 == o { n = 1 }')
            case "$_pca_v" in /*) [ -f "$_pca_v" ] && { printf '%s\n' "$_pca_v"; return 0; } ;; esac
        done
    done
    return 1
}

# apache_conf_path — 실행 중인 httpd/apache2 의 -f 설정 파일, 없으면 대표적인 설치 레이아웃(공식 도커/소스, Debian/Ubuntu,
# RHEL 계열) 순으로 탐색
apache_conf_path() {
    _proc_conf_arg "httpd apache2" -f && return 0
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

# nginx_conf_path — 실행 중인 nginx 의 -c 설정 파일(P-06), 없으면 대표 경로
nginx_conf_path() {
    _proc_conf_arg nginx -c && return 0
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

# nginx_error_page_gaps <설정 파일> -> error_page 가 있는데 404 를 지정하지 않은 블록마다 그 블록의 첫 error_page 줄 번호.
# nginx 는 한 블록에 error_page 가 하나라도 있으면 바깥 블록의 error_page 를 물려받지 않는다 - 기본 default.conf 처럼
# server 블록에 "error_page 500 502 503 504" 만 있으면 404 는 기본(버전 노출) 페이지다(실무 적용 검증 P-05: 예전에는
# error_page 줄이 하나라도 있으면 GOOD). 블록은 중괄호로 구분하고, 한 줄 블록(location / { error_page ...; })은 안쪽으로 본다.
nginx_error_page_gaps() {
    awk '
        { line = $0; sub(/#.*/, "", line)
          n = gsub(/\{/, "{", line); while (n-- > 0) { stack[++depth] = cur; cur = ++ids }
          if (match(line, /(^|[ \t;{])error_page[ \t][^;]*/)) {
              d = substr(line, RSTART, RLENGTH)
              if (!(cur in first)) first[cur] = FNR
              if (d ~ /[ \t]404([ \t]|$)/) has404[cur] = 1
          }
          n = gsub(/\}/, "}", line); while (n-- > 0 && depth > 0) cur = stack[depth--] }
        END { for (b in first) if (!(b in has404)) print first[b] }
    ' "$1" 2>/dev/null | sort -n
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
    # 실무 적용 검증 P-07: 한 서버에 인스턴스가 여러 개면 아래 탐색은 첫 인스턴스만 고른다. 운영자가 CATALINA_BASE 를 지정해
    # 실행하면(CATALINA_BASE=<경로> sh run.sh -e tomcat) 그 인스턴스를 진단한다 - run.sh 가 인스턴스 목록과 함께 안내한다.
    [ -n "${CATALINA_BASE:-}" ] && [ -d "$CATALINA_BASE/conf" ] && { echo "$CATALINA_BASE"; return 0; }
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

# tomcat_instances -> 실행 중인 Tomcat 인스턴스(CATALINA_BASE) 목록(중복 제거). 2개 이상이면 run.sh 가 인스턴스별 재실행을 안내한다.
tomcat_instances() {
    for _ti_pid in $(tomcat_pids); do
        tr '\000' '\n' 2>/dev/null < "/proc/$_ti_pid/cmdline" | sed -n 's/^-Dcatalina\.base=//p' | head -n 1
    done | awk 'NF && !s[$0]++'
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

# Tomcat 관리 화면(manager·host-manager)에 로그인할 수 있는 역할. 실무 적용 검증 P-04: 예전에는 manager-gui 만, 큰따옴표
# 속성만 봐서 manager-script/admin-gui 계정이나 작은따옴표로 쓴 <user> 요소가 "관리자 계정 없음"(GOOD)이 됐다.
TOMCAT_ADMIN_ROLE_RE='(manager|admin)-(gui|script|jmx|status)'

# tomcat_admin_user_elems <tomcat-users.xml> -> 관리 역할을 가진 <user> 요소를 한 줄에 하나씩(주석 제외).
# 요소는 따옴표 속성 단위로 자른다(값에 '>' 가 있어도 잘리지 않게). 큰따옴표·작은따옴표 속성 모두 인정한다.
tomcat_admin_user_elems() {
    strip_xml_comments "$1" | tr '\n' ' ' | \
        grep -oE "<user([[:space:]]+[A-Za-z_:.-]+[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*'))*[[:space:]]*/?>" | \
        grep -E "[[:space:]]roles[[:space:]]*=[[:space:]]*(\"[^\"]*|'[^']*)$TOMCAT_ADMIN_ROLE_RE"
}

# xml_attr <요소 문자열> <속성 이름> -> 속성 값(큰따옴표·작은따옴표 모두). 없으면 빈 출력.
xml_attr() {
    printf '%s' "$1" | sed -nE "s/.*[[:space:]]$2[[:space:]]*=[[:space:]]*(\"([^\"]*)\"|'([^']*)').*/\\2\\3/p"
}

# ---- 블록(범위) 단위 판정 헬퍼 (1.5.0 진단 신뢰성 A19~A22) ---------------------------
# 예전에는 "설정 파일 어딘가에 양호한 줄이 있으면 GOOD"(파일 단위 grep)이라, server/VirtualHost 하나에만 설정이 있고
# 다른 블록은 기본값(노출·허용)인 경우를 놓쳤다. 아래 함수들은 설정 상속 규칙을 반영해 "실제로 적용되는 값"을 블록마다 낸다.

# apache_option_effective <옵션> -> Options 가 적용되는 범위(<Directory> 등)마다 "ON|OFF<TAB>설명". 그 범위에 실제로 적용되는
# Options 집합을 Apache 병합 규칙대로 계산한다: 기본값 FollowSymLinks(2.4) → 서버 전역 Options → 상위 경로 <Directory> 들
# (짧은 경로부터) → 자기 Options. +/- 만 있는 줄은 상속값에 더하고 빼며, 표기 없는 줄은 상속값을 대체한다(All = Indexes
# Includes FollowSymLinks ExecCGI, None = 빈 집합, includes 를 물을 때 IncludesNOEXEC 도 켜진 것으로 본다).
# 예전 WEB-12 는 "Options -Indexes" 같은 상대 지정만 있어도 Options 가 있다고 보고 기본값 FollowSymLinks 를 놓쳤다(A19).
# 평가 대상: 자기 Options 가 있는 범위 + 모든 DocumentRoot 경로(자기 <Directory> Options 가 없어도 상위 경로·기본값을 물려받음).
# 둘 다 없으면 서버 전역 값 1줄. Options 없는 <Directory>(RHEL /var/www 처럼 직접 서비스하지 않는 상위 폴더)는 따로 평가하지 않는다.
# 한계: <Location>/<Files> 류는 <Directory> 병합을 거치지 않고 자기 Options 로 직접 켠 것만 본다, VirtualHost 별 전역 Options
# 차이는 구분하지 않는다, <IfModule> 등 조건부 블록은 활성으로 본다.
apache_option_effective() {
    apache_conf_stream | awk -F '\t' -v opt="$1" '
        function norm(p) { gsub(/"/, "", p); sub(/[ \t]+$/, "", p); if (p != "/") sub(/\/+$/, "", p); return p }
        function addw(set, x) { return index(set, " " x " ") ? set : set x " " }
        function delw(set, x) { sub(" " x " ", " ", set); return set }
        function apply(set, args,    n, a, i, rel, w, s, m, b, j) {
            n = split(args, a, /[ \t]+/); rel = 0
            for (i = 1; i <= n; i++) if (a[i] ~ /^[+-]/) rel = 1
            if (!rel) set = " "
            for (i = 1; i <= n; i++) {
                w = tolower(a[i]); s = ""
                if (w == "") continue
                if (w ~ /^[+-]/) { s = substr(w, 1, 1); w = substr(w, 2) }
                if (w == "none") continue
                if (w == "includesnoexec" && opt == "includes") w = "includes"
                if (w == "all") w = "indexes includes followsymlinks execcgi"
                m = split(w, b, " ")
                for (j = 1; j <= m; j++) set = (s == "-") ? delw(set, b[j]) : addw(set, b[j])
            }
            return set
        }
        function apply_all(set, ops,    n, a, i) {
            n = split(ops, a, "\n")
            for (i = 1; i <= n; i++) if (a[i] != "") set = apply(set, a[i])
            return set
        }
        function anc(p, q) { return p == "/" || q == p || substr(q, 1, length(p) + 1) == p "/" }
        function effdir(q,    nc, ch, j, x, y, tmp, e) {
            nc = 0
            for (j = 1; j <= ns; j++) if (st[j] == "dir" && has[j] && anc(sp[j], q)) { nc++; ch[nc] = j }
            for (x = 1; x <= nc; x++) for (y = x + 1; y <= nc; y++)
                if (length(sp[ch[y]]) < length(sp[ch[x]]) || (length(sp[ch[y]]) == length(sp[ch[x]]) && ch[y] < ch[x])) { tmp = ch[x]; ch[x] = ch[y]; ch[y] = tmp }
            e = base
            for (x = 1; x <= nc; x++) e = apply_all(e, ops[ch[x]])
            return e
        }
        BEGIN { opt = tolower(opt); depth = 0; cur[0] = 0 }
        { f = $1; ln = $2; t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
          if (t == "" || t ~ /^#/) next
          lt = tolower(t)
          if (lt ~ /^<\//) { if (depth > 0) depth--; next }
          if (lt ~ /^</) {
              name = lt; sub(/^</, "", name); sub(/[ \t>].*$/, "", name)
              arg = t; sub(/^<[^ \t>]+[ \t]*/, "", arg); sub(/>[ \t]*$/, "", arg)
              depth++
              if (name == "directory") { ns++; st[ns] = "dir"; sp[ns] = norm(arg); sl[ns] = f ":" ln " <Directory " arg ">"; cur[depth] = ns }
              else if (name ~ /^(directorymatch|location|locationmatch|files|filesmatch|proxy|proxymatch)$/) {
                  ns++; st[ns] = "other"; sl[ns] = f ":" ln " " t; cur[depth] = ns }
              else cur[depth] = cur[depth - 1]
              next
          }
          n = split(t, a, /[ \t]+/)
          if (tolower(a[1]) == "documentroot" && n >= 2) {
              d = t; sub(/^[^ \t]+[ \t]+/, "", d); d = norm(d)
              if (d != "" && !(d in seendr)) { seendr[d] = 1; nd++; dr[nd] = d; drl[nd] = f ":" ln }
          }
          if (tolower(a[1]) == "options") {
              args = t; sub(/^[^ \t]+[ \t]*/, "", args)
              c = cur[depth]
              if (c) { ops[c] = ops[c] "\n" args; has[c] = 1 } else gops = gops "\n" args
          } }
        END {
            base = apply_all(" followsymlinks ", gops); ev = 0
            for (i = 1; i <= ns; i++) {
                if (!has[i]) continue
                # <Location>/<Files> 류는 어느 <Directory> 위에 병합될지 알 수 없어 자기 Options 만 본다(빈 집합에서 시작 - +옵션·All·
                # 표기 없는 옵션으로 직접 켠 경우만 ON). RHEL welcome.conf 의 <LocationMatch> "Options -Indexes" 를 기본값 상속으로 오판하지 않게
                eff = (st[i] == "dir") ? effdir(sp[i]) : apply_all(" ", ops[i])
                ev++
                print (index(eff, " " opt " ") ? "ON" : "OFF") "\t" sl[i] " => Options" (eff == " " ? " None" : eff)
            }
            for (k = 1; k <= nd; k++) {
                eff = effdir(dr[k]); ev++
                print (index(eff, " " opt " ") ? "ON" : "OFF") "\t" drl[k] " DocumentRoot " dr[k] " (상위 경로·기본값 상속 포함) => Options" (eff == " " ? " None" : eff)
            }
            if (!ev) print (index(base, " " opt " ") ? "ON" : "OFF") "\t(서버 전역 - Options 지정 범위·DocumentRoot 없음, 기본값 FollowSymLinks" (gops != "" ? " + 전역 Options" : "") ") => Options" (base == " " ? " None" : base)
        }'
}

# apache_vhost_scopes <상속 ERE> [비상속 ERE] -> 서버 전역(main)과 <VirtualHost> 마다 지시자 유무(소문자로 바꾼 줄에 ERE 대조).
#   MAIN<TAB>평문포트_main필요(0/1)<TAB>main필요(0/1)<TAB>전역SSL<TAB>전역 상속ERE<TAB>전역 비상속ERE
#   VH<TAB>설명<TAB>SSL(SSLEngine on)<TAB>상속ERE<TAB>비상속ERE<TAB>RewriteOptions Inherit
# Apache 는 서버 전역 설정(ErrorDocument, mod_alias Redirect 등)을 VirtualHost 가 물려받지만 RewriteRule 은 RewriteOptions
# Inherit 가 없으면 물려받지 않는다. main(VirtualHost 밖)은 어느 VirtualHost 도 받지 않는 Listen 포트가 있을 때만 요청을 받는다
# (443·"https" Listen 은 SSL 포트로 본다). 예전 WEB-21/22 는 VirtualHost 하나에만 설정이 있어도 GOOD 이었다(A20).
apache_vhost_scopes() {
    apache_conf_stream | awk -F '\t' -v inh="$1" -v non="${2:-}" '
        { f = $1; ln = $2; t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
          if (t == "" || t ~ /^#/) next
          lt = tolower(t)
          if (lt ~ /^<virtualhost[ \t>]/) {
              nv++; iv = nv; ad = t; sub(/^<[^ \t>]+[ \t]*/, "", ad); sub(/>.*$/, "", ad)
              vl[nv] = f ":" ln " <VirtualHost " ad ">"
              m = split(ad, aa, /[ \t]+/)
              for (i = 1; i <= m; i++) { p = aa[i]; if (p ~ /\]$/ || index(p, ":") == 0) p = "*"; else sub(/^.*:/, "", p); vp[nv] = vp[nv] " " p " "; if (p == "*") anyport = 1 }
              next
          }
          if (lt ~ /^<\/virtualhost/) { iv = 0; next }
          n = split(t, a, /[ \t]+/); k = tolower(a[1])
          if (k == "listen" && n >= 2) { p = a[2]; sub(/^.*:/, "", p); lp[p] = (p == "443" || tolower(a[3]) == "https") ? "ssl" : "plain"; nl++ }
          if (k == "sslengine" && tolower(a[2]) == "on") { if (iv) vs[iv] = 1; else gs = 1 }
          if (lt ~ inh) { if (iv) vi[iv] = 1; else gi = 1 }
          if (non != "" && lt ~ non) { if (iv) vn[iv] = 1; else gn = 1 }
          if (iv && k == "rewriteoptions" && lt ~ /inherit/) vr[iv] = 1
        }
        END {
            for (p in lp) {
                cov = anyport
                for (i = 1; i <= nv && !cov; i++) if (index(vp[i], " " p " ")) cov = 1
                if (!cov) { na = 1; if (lp[p] == "plain") np = 1 }
            }
            if (!nl && !nv) { na = 1; np = 1 }
            print "MAIN\t" (np + 0) "\t" (na + 0) "\t" (gs + 0) "\t" (gi + 0) "\t" (gn + 0)
            for (i = 1; i <= nv; i++) print "VH\t" vl[i] "\t" (vs[i] + 0) "\t" (vi[i] + 0) "\t" (vn[i] + 0) "\t" (vr[i] + 0)
        }'
}

# apache_https_redirect_scopes -> 평문(HTTP) 요청을 받는 범위마다 "OK|BAD<TAB>설명" (WEB-21 진단·조치 공통 기준).
# 리다이렉트 = 대상이 https:// 인 Redirect/RedirectMatch/RedirectPermanent/RedirectTemp(서버 전역 것은 VirtualHost 가 물려받음)
# 또는 RewriteRule(서버 전역 것은 RewriteOptions Inherit 인 VirtualHost 만 물려받음). SSL(SSLEngine on) VirtualHost 는 대상 아님.
apache_https_redirect_scopes() {
    apache_vhost_scopes '^redirect(match|permanent|temp)?[ \t].*[ \t]"?https://' '^rewriterule[ \t].*[ \t]"?https://' | awk -F '\t' '
        $1 == "MAIN" { np = $2; gs = $4; gi = $5; gn = $6; next }
        $1 == "VH" { n++; l[n] = $2; s[n] = $3; i[n] = $4; r[n] = $5; ri[n] = $6 }
        END {
            for (k = 1; k <= n; k++) {
                if (s[k]) { print "OK\t" l[k] " (SSL)"; continue }
                if (i[k] || r[k]) print "OK\t" l[k] " (자체 리다이렉트)"
                else if (gi) print "OK\t" l[k] " (서버 전역 Redirect 상속)"
                else if (ri[k] && gn) print "OK\t" l[k] " (서버 전역 RewriteRule 상속 - RewriteOptions Inherit)"
                else print "BAD\t" l[k]
            }
            if (np && !gs) print ((gi || gn) ? "OK" : "BAD") "\t서버 전역(VirtualHost 가 받지 않는 평문 Listen 포트)"
            else if (!n) print "OK\t서버 전역(평문 Listen 포트 없음 - SSL 전용)"
        }'
}

# _nginx_include_map <메인 설정> -> "부모파일<TAB>include 인자<TAB>펼친 파일" (nginx_scoped_stmts 가 include 자리에서 펼칠 때 쓴다)
_nginx_include_map() {
    _nim_base=$(dirname "$1")
    web_conf_files nginx 2>/dev/null | while IFS= read -r _nim_f; do
        [ -f "$_nim_f" ] || continue
        awk '{ sub(/\r$/, ""); sub(/#.*/, ""); s = $0
               while (match(s, /(^|[ \t;{}])include[ \t]+[^;]+;/)) {
                   p = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
                   sub(/^[ \t;{}]*include[ \t]+/, "", p); sub(/[ \t]*;$/, "", p); gsub(/["\047]/, "", p); print p } }' "$_nim_f" 2>/dev/null | \
        while IFS= read -r _nim_p; do
            _nim_abs=$_nim_p
            case "$_nim_abs" in /*) ;; *) _nim_abs="$_nim_base/$_nim_abs" ;; esac
            _web_expand_pattern "$_nim_abs" | while IFS= read -r _nim_c; do
                printf '%s\t%s\t%s\n' "$_nim_f" "$_nim_p" "$_nim_c"
            done
        done
    done
}

# nginx_scoped_stmts -> nginx 설정을 include 자리에서 펼쳐(nginx 가 읽는 순서·블록 그대로) 지시자마다 범위를 붙여 출력한다.
#   SRV<TAB>server번호<TAB>파일:줄                         (http 바로 아래 server 블록)
#   DIR<TAB>범위<TAB>server번호<TAB>파일:줄<TAB>지시자 인자...  범위: main|http|server|inner(server 안 location·if 등)|other
#   TRUNC / ERRF<TAB>파일                                  (include 깊이 16·파일 512 상한 / 읽기 실패)
# 따옴표·# 주석·여러 줄 지시자·한 줄 여러 지시자·${var} 를 처리한다. 같은 파일을 여러 곳에서 include 하면 그 자리마다 펼친다
# (순환만 막는다 - nginx 와 같다).
nginx_scoped_stmts() {
    _nss_main=$(nginx_conf_path) || return 1
    NGX_MAP=$(_nginx_include_map "$_nss_main") awk -v main="$_nss_main" '
        function addword() { if (inword) { nw++; w[nw] = cur; if (nw == 1) { sf = cf; sl = cl } } cur = ""; inword = 0 }
        function scope() {
            if (sd == 0) return "main"
            if (stk[sd] == "http") return "http"
            if (stk[sd] == "server" && sd >= 2 && stk[sd - 1] == "http") return "server"
            if (ssid[sd] > 0) return "inner"
            return "other"
        }
        function stmt(    i, s, ks, n, kids, k, f2) {
            if (nw == 0) return
            if (w[1] == "include" && nw >= 2) {
                ks = map[sf SUBSEP w[2]]; nw = 0
                n = split(ks, kids, "\n")
                for (k = 1; k <= n; k++) { f2 = kids[k]; if (f2 != "" && !(f2 in onstack)) proc(f2, curdepth + 1) }
                return
            }
            s = w[1]; for (i = 2; i <= nw; i++) s = s " " w[i]
            print "DIR\t" scope() "\t" (ssid[sd] + 0) "\t" sf ":" sl "\t" s
            nw = 0
        }
        function openb(    name) {
            name = (nw >= 1) ? w[1] : ""
            sd++; stk[sd] = name; ssid[sd] = ssid[sd - 1]
            if (name == "server" && sd >= 2 && stk[sd - 1] == "http") { nsrv++; ssid[sd] = nsrv; print "SRV\t" nsrv "\t" sf ":" sl }
            nw = 0
        }
        function scanline(f, ln, l,    i, c, n) {
            n = length(l)
            for (i = 1; i <= n; i++) {
                c = substr(l, i, 1)
                if (inq != "") {
                    if (c == "\\") { cur = cur substr(l, i + 1, 1); i++; continue }
                    if (c == inq) { inq = ""; continue }
                    cur = cur c; continue
                }
                if (c == "\"" || c == "\047") { if (!inword) { inword = 1; cf = f; cl = ln } inq = c; continue }
                if (c == " " || c == "\t" || c == "\r") { addword(); continue }
                if (c == "#" && !inword) break
                if (c == ";") { addword(); stmt(); continue }
                if (c == "{") {
                    if (inword && substr(cur, length(cur), 1) == "$") { cur = cur c; invar = 1; continue }
                    addword(); openb(); continue
                }
                if (c == "}") {
                    if (invar) { cur = cur c; invar = 0; continue }
                    addword(); stmt(); if (sd > 0) sd--; continue
                }
                if (!inword) { inword = 1; cf = f; cl = ln }
                cur = cur c
            }
            if (inq == "") addword()
        }
        function proc(f, depth,    l, ln, rc, od) {
            if (depth > 16 || loads >= 512) { print "TRUNC"; return }
            loads++; onstack[f] = 1; od = curdepth; curdepth = depth; ln = 0
            while ((rc = (getline l < f)) > 0) { ln++; scanline(f, ln, l) }
            if (rc < 0) print "ERRF\t" f
            close(f); delete onstack[f]; curdepth = od
        }
        BEGIN {
            n = split(ENVIRON["NGX_MAP"], ml, "\n")
            for (i = 1; i <= n; i++) { if (split(ml[i], p, "\t") >= 3) map[p[1] SUBSEP p[2]] = map[p[1] SUBSEP p[2]] p[3] "\n" }
            proc(main, 0)
            exit
        }'
}

# nginx_server_effective <지시자> <기본값> [multi] -> http 아래 server 블록마다 실제로 적용되는 값(server 블록 값, 없으면
# http 블록 값, 둘 다 없으면 기본값 - nginx 상속 규칙). multi 를 주면 같은 블록의 여러 줄을 " | " 로 이어 하나의 값으로
# 본다(error_page 처럼 블록에 하나라도 있으면 바깥 값을 물려받지 않는 지시자).
#   SRV<TAB>server 설명(파일:줄 server_name)<TAB>적용값<TAB>출처(server 파일:줄 | http 파일:줄 | 기본값)
#   INNER<TAB>파일:줄<TAB>값       (server 안 location·if 등에서 다시 지정한 값 - 그 범위에서는 이 값이 적용됨)
# server 블록이 하나도 없으면 http 값(없으면 기본값) 한 줄을 SRV 로 낸다.
nginx_server_effective() {
    nginx_scoped_stmts | awk -F '\t' -v d="$1" -v def="$2" -v multi="${3:-}" '
        $1 == "SRV" { ns++; id[ns] = $2; lab[$2] = $3; next }
        $1 != "DIR" { next }
        { s = $5; k = s; sub(/ .*/, "", k); v = ""; if (index(s, " ")) { v = s; sub(/^[^ ]+ /, "", v) } }
        k == "server_name" && $2 == "server" { if (!($3 in sn)) sn[$3] = v; next }
        k != d { next }
        $2 == "http" { hv = (multi != "" && hset) ? hv " | " v : v; hset = 1; hloc = $4; next }
        $2 == "server" { nv = (multi != "" && ($3 in sv)) ? sv[$3] " | " v : v; sv[$3] = nv; sloc[$3] = $4; next }
        $2 == "inner" { print "INNER\t" $4 "\t" v; next }
        END {
            if (ns == 0) print "SRV\t(server 블록 없음 - http)\t" (hset ? hv : def) "\t" (hset ? "http " hloc : "기본값")
            for (i = 1; i <= ns; i++) {
                s = id[i]; L = lab[s] ((s in sn) ? " server_name " sn[s] : "")
                if (s in sv) print "SRV\t" L "\t" sv[s] "\tserver " sloc[s]
                else if (hset) print "SRV\t" L "\t" hv "\thttp " hloc
                else print "SRV\t" L "\t" def "\t기본값"
            }
        }'
}

# nginx_https_redirect_servers -> http 아래 server 블록마다 "OK|BAD<TAB>설명" (WEB-21 진단·조치 공통 기준). ssl 이 아닌 listen 이
# 있거나 listen 이 없는(기본 80) server 블록은 그 블록 또는 안쪽 location 등에 return 30x https://… / rewrite … https://… 가
# 있어야 한다(return·rewrite 는 http 블록에서 물려받지 않는다). server 블록이 없으면 출력 없음.
nginx_https_redirect_servers() {
    nginx_scoped_stmts | awk -F '\t' '
        $1 == "SRV" { n++; id[n] = $2; lab[$2] = $3; next }
        $1 != "DIR" || ($2 != "server" && $2 != "inner") { next }
        { s = $5; k = s; sub(/ .*/, "", k) }
        $2 == "server" && k == "listen" { nl[$3]++; if (s !~ /[ ]ssl( |$)/) plain[$3] = 1 }
        $2 == "server" && k == "server_name" && !($3 in sn) { sn[$3] = s; sub(/^server_name /, "", sn[$3]) }
        (k == "return" && s ~ /^return 30[1278] "?https:\/\//) || (k == "rewrite" && s ~ / "?https:\/\//) { rd[$3] = 1; where[$3] = $4 }
        END {
            for (i = 1; i <= n; i++) {
                v = id[i]; L = lab[v] ((v in sn) ? " server_name " sn[v] : "")
                if (nl[v] && !plain[v]) print "OK\t" L " (ssl 전용)"
                else if (rd[v]) print "OK\t" L " (리다이렉트 " where[v] ")"
                else print "BAD\t" L
            }
        }'
}

# tomcat_context_xmls <conf 폴더> -> 컨텍스트 설정 파일: conf/context.xml(모든 웹앱 공통) + conf/<Engine>/<Host>/*.xml(앱별
# 컨텍스트 디스크립터 - conf/Catalina/localhost/app.xml). 예전 WEB-06/12/13 은 server.xml·context.xml 만 봐 앱별 컨텍스트의
# allowLinking·<Resource> 를 놓쳤다(A21). 있는 파일만(읽기 가능 여부는 호출 측이 확인).
tomcat_context_xmls() {
    [ -f "$1/context.xml" ] && printf '%s\n' "$1/context.xml"
    for _tcx in "$1"/*/*/*.xml; do
        [ -f "$_tcx" ] && printf '%s\n' "$_tcx"
    done
    return 0
}

# Tomcat allowLinking="true"(큰·작은따옴표·따옴표 없음 모두, grep -iE 용) - 예전에는 작은따옴표를 놓쳤다(A21)
TOMCAT_ALLOWLINKING_TRUE_RE="allowLinking[[:space:]]*=[[:space:]]*[\"']?true"

# tomcat_http_connectors <server.xml> -> AJP 가 아닌(HTTP) <Connector> 요소를 한 줄에 하나씩(주석 제외, 여러 줄 요소는 한 줄로).
# 따옴표 속성 단위로 잘라 값에 '>' 가 있어도 잘리지 않는다. 예전 WEB-08/16 은 Connector 하나에만 속성이 있어도 GOOD 이었다(A22).
tomcat_http_connectors() {
    strip_xml_comments "$1" | tr '\n\r' '  ' | \
        grep -oE "<Connector([[:space:]]+[A-Za-z_:.-]+[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*'))*[[:space:]]*/?>" | \
        grep -viE "[[:space:]]protocol[[:space:]]*=[[:space:]]*[\"'][^\"']*AJP"
}

# tomcat_connectors_add_attr <server.xml> <속성> <값> [건너뛸 속성 ERE] -> 그 속성(또는 ERE 에 맞는 속성)이 없는 HTTP <Connector>
# 마다 "<Connector" 바로 뒤에 속성을 넣은 내용을 표준 출력으로(파일은 바꾸지 않음 - 조치가 fix_write_back 으로 반영).
# 주석 안의 Connector·AJP 는 건너뛴다. 여러 줄 요소는 닫는 '>' 가 나올 때까지 모아 판단하고, 여는 줄에서 삽입한다
# (닫는 '>' 앞 삽입은 여러 줄 태그에서 실패 - 03_web/CLAUDE.md).
tomcat_connectors_add_attr() {
    awk -v attr="$2" -v val="$3" -v skip="${4:-$2}" '
        function decide(first, el) {
            if (el !~ ("[ \t]" skip "[ \t]*=") && tolower(el) !~ /[ \t]protocol[ \t]*=[ \t]*["\047][^"\047]*ajp/)
                sub(/<Connector/, "<Connector " attr "=\"" val "\"", first)
            return first
        }
        inel { el = el " " $0; buf = buf "\n" $0; if (index($0, ">")) { print decide(first, el) buf; inel = 0 } ; next }
        {
            line = $0; vis = ""
            while (line != "") {
                if (incomment) { p = index(line, "-->"); if (!p) { line = ""; break } line = substr(line, p + 3); incomment = 0; continue }
                p = index(line, "<!--"); if (!p) { vis = vis line; line = ""; break }
                vis = vis substr(line, 1, p - 1); line = substr(line, p + 4); incomment = 1
            }
            p = index(vis, "<Connector")
            if (!p) { print; next }
            el = substr(vis, p)
            if (index(el, ">")) { print decide($0, el); next }
            first = $0; buf = ""; inel = 1
        }
        END { if (inel) print first buf }' "$1"
}

# 추측하기 쉬운 관리자 계정명(WEB-01, A23): 가이드 기본 계정(tomcat/admin, JEUS administrator) + 흔한 관리·예시 계정명.
# Tomcat 기본 tomcat-users.xml 예시(tomcat, both, role1)와 manager/robot 같은 역할·예시 이름을 포함한다(대소문자 무시 정확히 일치).
TOMCAT_DEFAULT_ADMIN_RE='admin|tomcat|administrator'
TOMCAT_GUESSABLE_ADMIN_RE='admin|tomcat|administrator|manager|root|robot|both|role1|test|tester|guest|user|demo|sysadmin|system|operator|master|super|superuser|webadmin|web'
