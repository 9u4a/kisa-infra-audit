# WEB-19 (중) 웹 서비스 SSI(Server Side Includes) 사용 제한
# 판단 기준(가이드 원문): 양호 = SSI 비활성화 / 취약 = 활성화

run_check() {
    detect_web_engines
    violations=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*Options[^#]*\bIncludes\b' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Apache] Options Includes 검색: ${hit:-없음}"
        [ -n "$hit" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*ssi[[:space:]]+on' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Nginx] ssi on 검색: ${hit:-없음(기본값 off)}"
        [ -n "$hit" ] && violations="$violations nginx"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        hit=""
        [ -f "$f" ] && hit=$(strip_xml_comments "$f" | grep -E 'SSIServlet|SSIFilter')
        evidence="$evidence
[Tomcat] SSI 서블릿/필터: ${hit:-없음(기본값 비활성)}"
        [ -n "$hit" ] && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="SSI 가 활성화된 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="SSI 가 비활성화되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}
