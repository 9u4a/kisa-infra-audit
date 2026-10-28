# WEB-05 (상) 지정하지 않은 CGI/ISAPI 실행 제한
# 판단 기준(가이드 원문): 양호 = CGI 미사용 또는 실행 가능 디렉터리를 제한한 경우
#                        취약 = CGI 사용하며 제한하지 않은 경우
# "제한 디렉터리 적절성"은 업무 판단이 필요해, 모듈/설정 활성 여부까지만 자동 판정하고
# 활성 상태면 실제 제한 범위는 MANUAL 로 안내한다.
# Tomcat 은 XML 주석을 먼저 지운 뒤 cgi servlet-mapping 을 찾는다 - 예전에는 기본 web.xml 의 주석 속 예시를
# 활성으로 봐 항상 MANUAL 이었다(진단 검수 WEB-R11).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            cgi_on=""
            for f in $WEB_FILES; do
                hit=$(grep -niE '^[^#]*LoadModule[[:space:]]+cgid?_module' "$f" 2>/dev/null)
                [ -n "$hit" ] && cgi_on="$cgi_on
$f: $hit"
            done
            evidence="$evidence
[Apache] cgi 모듈 로드: ${cgi_on:-미사용}"
            [ -n "$cgi_on" ] && manuals="$manuals apache(cgi 모듈 활성 - 디렉터리 제한 범위 수동 확인 필요)"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            fcgi_on=""
            for f in $WEB_FILES; do
                hit=$(grep -nE '^[^#]*fastcgi_pass' "$f" 2>/dev/null)
                [ -n "$hit" ] && fcgi_on="$fcgi_on
$f: $hit"
            done
            evidence="$evidence
[Nginx] fastcgi_pass 사용: ${fcgi_on:-미사용}"
            [ -n "$fcgi_on" ] && manuals="$manuals nginx(fastcgi 활성 - 범위 수동 확인 필요)"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf web.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | tr '\n' ' ' | \
                grep -oE '<servlet-mapping>[[:space:]]*<servlet-name>[[:space:]]*cgi[[:space:]]*</servlet-name>[[:space:]]*<url-pattern>[^<]*</url-pattern>')
            evidence="$evidence
[Tomcat] $TC_FILE cgi servlet-mapping: ${hit:-비활성/미설정}"
            [ -n "$hit" ] && manuals="$manuals tomcat(cgi 매핑 활성 - 범위 수동 확인 필요)"
        fi
    esac

    web_finish "CGI 를 제한 없이 사용하는 엔진" "CGI 를 사용하지 않음" "CGI 관련 모듈/설정이 활성화됨 — 실행 가능 디렉터리 제한 여부 수동 확인 필요"
}
