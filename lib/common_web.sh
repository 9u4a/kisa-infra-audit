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
