# WEB-22 (하) 에러 페이지 관리
# 판단 기준(가이드 원문): 양호 = 에러 페이지가 별도로 지정됨 / 취약 = 미지정 또는 정보 노출

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
            l=$(grep -nE '^[^#]*ErrorDocument' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Apache] ErrorDocument 검색: ${hit:-없음}"
        [ -z "$hit" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*error_page' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Nginx] error_page 검색: ${hit:-없음}"
        [ -z "$hit" ] && violations="$violations nginx"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        hit=""
        [ -f "$f" ] && hit=$(strip_xml_comments "$f" | grep -c '<error-page>')
        evidence="$evidence
[Tomcat] error-page 요소 개수: ${hit:-0}"
        { [ -z "$hit" ] || [ "$hit" -eq 0 ]; } && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="에러 페이지가 별도로 지정되지 않은 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="에러 페이지가 별도로 지정되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}
