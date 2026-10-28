# WEB-19 (중) 웹 서비스 SSI(Server Side Includes) 사용 제한
# 판단 기준(가이드 원문): 양호 = SSI 비활성화 / 취약 = 활성화
# Apache: Options 의 Includes·+Includes·IncludesNOEXEC·All(Includes 포함), -Includes 는 제외(진단 검수 WEB-R10).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            # shellcheck disable=SC2086
            hit=$(web_apache_option_hits Includes $WEB_FILES)
            evidence="$evidence
[Apache] Options Includes/All 검색: ${hit:-없음}"
            [ -n "$hit" ] && violations="$violations apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*ssi[[:space:]]+on' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] ssi on 검색: ${hit:-없음(기본값 off)}"
            [ -n "$hit" ] && violations="$violations nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf web.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -E 'SSIServlet|SSIFilter')
            evidence="$evidence
[Tomcat] SSI 서블릿/필터: ${hit:-없음(기본값 비활성)}"
            [ -n "$hit" ] && violations="$violations tomcat"
        fi
    esac

    web_finish "SSI 가 활성화된 엔진" "SSI 가 비활성화되어 있음"
}
