# WEB-11 (중) 웹 서비스 경로 설정
# 판단 기준(가이드 원문): 양호 = DocumentRoot 가 업무 영역과 분리된 별도 경로 / 취약 = 기본 경로 사용
# 자동화 범위: Apache/Nginx 는 실제 로드되는 모든 설정(가상호스트 포함)의 DocumentRoot/root 중 잘 알려진 기본
# 경로가 하나라도 있으면 VULN - 예전에는 Apache 메인 설정의 마지막 DocumentRoot 만 봐 Debian sites-enabled 의
# /var/www/html 을 놓쳤다(진단 검수 WEB-R10). 지시자를 못 찾으면(컴파일 기본값) MANUAL.
# Tomcat(1.4.0, 커버리지 검수 WEB-C2): 예전에는 항상 MANUAL 이었다. 가이드 조치(Context docBase 를 별도 경로로)에 맞춰
# Apache/Nginx 의 "기본 경로 사용 = VULN" 과 같은 기준으로 본다 - 루트 컨텍스트(<Context path="">/"/", 또는
# conf/<Engine>/<Host>/ROOT.xml)의 docBase 가 CATALINA_BASE/webapps 밖의 절대 경로이거나, Host appBase 가 기본값
# (webapps)이 아닌 별도 절대 경로면 GOOD, 기본 appBase(webapps)를 그대로 쓰면 VULN.

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0
    default_paths='^/usr/local/apache2/htdocs/?$|^/var/www/html/?$|^/var/www/?$|^/usr/share/nginx/html/?$|^/usr/local/nginx/html/?$'

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            roots=""
            for f in $WEB_FILES; do
                r=$(awk '{ t = $0; sub(/^[ \t]+/, "", t); n = split(t, a, /[ \t]+/)
                         if (n >= 2 && tolower(a[1]) == "documentroot") { v = a[2]; gsub(/"/, "", v); print v } }' "$f" 2>/dev/null)
                [ -n "$r" ] && roots="$roots
$f: $(printf '%s' "$r" | tr '\n' ' ')"
            done
            evidence="$evidence
[Apache] DocumentRoot: ${roots:-미지정}"
            if [ -z "$roots" ]; then
                manuals="$manuals apache(DocumentRoot 지시자를 찾지 못함 - 컴파일 기본 경로 사용 여부 수동 확인)"
            elif printf '%s\n' "$roots" | sed 's/^[^:]*: //' | tr ' ' '\n' | grep -qE "$default_paths"; then
                violations="$violations apache(기본 경로 사용)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            roots=""
            for f in $WEB_FILES; do
                r=$(awk '{ sub(/#.*/, ""); s = $0
                           while (match(s, /(^|[ \t;{}])root[ \t]+[^;]+;/)) {
                               p = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
                               sub(/^[ \t;{}]*root[ \t]+/, "", p); sub(/[ \t]*;$/, "", p); gsub(/"/, "", p); print p } }' "$f" 2>/dev/null)
                [ -n "$r" ] && roots="$roots
$f: $(printf '%s' "$r" | tr '\n' ' ')"
            done
            evidence="$evidence
[Nginx] root: ${roots:-미지정}"
            if [ -z "$roots" ]; then
                manuals="$manuals nginx(root 지시자를 찾지 못함 - 기본 경로(<prefix>/html) 사용 여부 수동 확인)"
            elif printf '%s\n' "$roots" | sed 's/^[^:]*: //' | tr ' ' '\n' | grep -qE "$default_paths"; then
                violations="$violations nginx(기본 경로 사용)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            tc_base=$(dirname "$(dirname "$TC_FILE")")
            tc_home=$(tomcat_home) || tc_home=$tc_base
            flat=$(strip_xml_comments "$TC_FILE" | tr '\n\r\t' '   ')
            appbases=$(printf '%s' "$flat" | grep -oE '<Host[[:space:]][^>]*>' | sed -nE 's/.*[[:space:]]appBase[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p')
            roots=$(printf '%s' "$flat" | grep -oE '<Context[[:space:]][^>]*>' | grep -E '[[:space:]]path[[:space:]]*=[[:space:]]*"/?"' | \
                sed -nE 's/.*[[:space:]]docBase[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p')
            for rx in "$(dirname "$TC_FILE")"/*/*/ROOT.xml; do
                [ -r "$rx" ] || continue
                r=$(strip_xml_comments "$rx" | tr '\n\r\t' '   ' | grep -oE '<Context[[:space:]][^>]*>' | sed -nE 's/.*[[:space:]]docBase[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p')
                [ -n "$r" ] && roots="$roots
$r"
            done
            evidence="$evidence
[Tomcat] $TC_FILE Host appBase: $(printf '%s' "${appbases:-미지정(기본값 webapps)}" | tr '\n' ' ') / 루트 컨텍스트 docBase: $(printf '%s' "${roots:-없음}" | tr '\n' ' ')"
            sep=""
            for r in $roots; do
                case "$r" in
                    "$tc_home"/webapps|"$tc_home"/webapps/*|"$tc_base"/webapps|"$tc_base"/webapps/*) ;;
                    /*) sep=1 ;;
                esac
            done
            if [ -z "$sep" ]; then
                deflt=""
                [ -z "$appbases" ] && deflt=1
                for ab in $appbases; do
                    case "$ab" in
                        webapps|webapps/|"$tc_home"/webapps|"$tc_home"/webapps/|"$tc_base"/webapps|"$tc_base"/webapps/) deflt=1 ;;
                        /*) ;;
                        *) deflt=1 ;;
                    esac
                done
                [ -n "$deflt" ] && violations="$violations tomcat(기본 appBase webapps 사용, 루트 컨텍스트 docBase 미분리)"
            fi
        fi
    esac

    web_finish "기본 경로를 그대로 사용 중" "웹 경로가 기본 경로와 분리되어 있음"
}
