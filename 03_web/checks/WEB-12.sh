# WEB-12 (중) 웹 서비스 링크 사용 금지
# 판단 기준(가이드 원문): 양호 = 심볼릭 링크/aliases/바로가기 사용 미허용 / 취약 = 허용

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
            l=$(grep -nE '^[^#]*Options[^#]*FollowSymLinks' "$f" 2>/dev/null | grep -v '\-FollowSymLinks')
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Apache] FollowSymLinks 검색: ${hit:-없음}"
        [ -n "$hit" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*disable_symlinks[[:space:]]+on' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Nginx] disable_symlinks on 검색: ${hit:-없음(기본값: 제한 없음 = 심볼릭 링크 허용됨)}"
        [ -z "$hit" ] && violations="$violations nginx(disable_symlinks 미설정)"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        hit=""
        [ -f "$f" ] && hit=$(strip_xml_comments "$f" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true')
        evidence="$evidence
[Tomcat] allowLinking=true 검색: ${hit:-없음(기본값 false)}"
        [ -n "$hit" ] && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="심볼릭 링크/링크 사용이 허용된 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="심볼릭 링크 사용이 제한되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}
