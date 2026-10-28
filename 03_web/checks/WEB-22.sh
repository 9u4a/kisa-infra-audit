# WEB-22 (하) 에러 페이지 관리
# 판단 기준(가이드 원문): 양호 = 에러 페이지가 별도로 지정됨 / 취약 = 미지정 또는 정보 노출

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*ErrorDocument' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] ErrorDocument 검색: ${hit:-없음}"
            [ -z "$hit" ] && violations="$violations apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*error_page' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] error_page 검색: ${hit:-없음}"
            [ -z "$hit" ] && violations="$violations nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf web.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -c '<error-page>')
            evidence="$evidence
[Tomcat] $TC_FILE error-page 요소 개수: ${hit:-0}"
            { [ -z "$hit" ] || [ "$hit" -eq 0 ]; } && violations="$violations tomcat"
        fi
    esac

    web_finish "에러 페이지가 별도로 지정되지 않은 엔진" "에러 페이지가 별도로 지정되어 있음"
}
