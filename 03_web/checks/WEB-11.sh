# WEB-11 (중) 웹 서비스 경로 설정
# 판단 기준(가이드 원문): 양호 = DocumentRoot 가 업무 영역과 분리된 별도 경로 / 취약 = 기본 경로 사용
# 자동화 범위: Apache/Nginx 는 실제 로드되는 모든 설정(가상호스트 포함)의 DocumentRoot/root 중 잘 알려진 기본
# 경로가 하나라도 있으면 VULN - 예전에는 Apache 메인 설정의 마지막 DocumentRoot 만 봐 Debian sites-enabled 의
# /var/www/html 을 놓쳤다(진단 검수 WEB-R10). 지시자를 못 찾으면(컴파일 기본값) MANUAL.
# Tomcat 은 appBase="webapps" 자체가 정상 배치 구조라 "분리 여부"를 자동 판정하기 어려워 MANUAL 로 안내한다.

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
        manuals="$manuals tomcat(appBase=webapps 자체는 표준 구조이므로 영역 분리 여부는 배포 구성 수동 확인 필요)"
    esac

    web_finish "기본 경로를 그대로 사용 중" "웹 경로가 기본 경로와 분리되어 있음"
}
