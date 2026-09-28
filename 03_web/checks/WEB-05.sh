# WEB-05 (상) 지정하지 않은 CGI/ISAPI 실행 제한
# 판단 기준(가이드 원문): 양호 = CGI 미사용 또는 실행 가능 디렉터리를 제한한 경우
#                        취약 = CGI 사용하며 제한하지 않은 경우
# "제한 디렉터리 적절성"은 업무 판단이 필요해, 모듈/설정 활성 여부까지만 자동 판정하고
# 활성 상태면 실제 제한 범위는 MANUAL 로 안내한다.

run_check() {
    detect_web_engines
    violations=""
    manuals=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        cgi_on=""
        for f in $files; do
            [ -f "$f" ] || continue
            hit=$(grep -nE '^[^#]*LoadModule[[:space:]]+cgid?_module' "$f" 2>/dev/null)
            [ -n "$hit" ] && cgi_on="$cgi_on
$f: $hit"
        done
        evidence="$evidence
[Apache] cgi 모듈 로드: ${cgi_on:-미사용}"
        [ -n "$cgi_on" ] && manuals="$manuals apache(cgi 모듈 활성 - 디렉터리 제한 범위 수동 확인 필요)"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        fcgi_on=""
        for f in $files; do
            [ -f "$f" ] || continue
            hit=$(grep -nE '^[^#]*fastcgi_pass' "$f" 2>/dev/null)
            [ -n "$hit" ] && fcgi_on="$fcgi_on
$f: $hit"
        done
        evidence="$evidence
[Nginx] fastcgi_pass 사용: ${fcgi_on:-미사용}"
        [ -n "$fcgi_on" ] && manuals="$manuals nginx(fastcgi 활성 - 범위 수동 확인 필요)"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        hit=""
        if [ -f "$f" ]; then
            hit=$(awk '/servlet-name>cgi</{f=1} f{print} /\/servlet-mapping>/{if(f)exit}' "$f" | grep -v '<!--')
        fi
        evidence="$evidence
[Tomcat] cgi servlet-mapping: ${hit:-비활성/미설정}"
        [ -n "$hit" ] && manuals="$manuals tomcat(cgi 매핑 활성 - 범위 수동 확인 필요)"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$manuals" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="CGI 관련 모듈/설정이 활성화됨 — 실행 가능 디렉터리 제한 여부 수동 확인 필요:$manuals"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="CGI 를 사용하지 않음"
    fi
    CHECK_EVIDENCE="$evidence"
}
