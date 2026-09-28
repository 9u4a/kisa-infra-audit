# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한
# 판단 기준(가이드 원문): 양호 = HTTP 응답 헤더에서 웹 서버 정보가 노출되지 않음
#                        취약 = 노출됨

run_check() {
    detect_web_engines
    violations=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        tokens=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*ServerTokens[[:space:]]+Prod' "$f" 2>/dev/null)
            [ -n "$l" ] && tokens="$tokens
$f: $l"
        done
        evidence="$evidence
[Apache] ServerTokens Prod 검색: ${tokens:-없음(기본값 Full - 상세 정보 노출)}"
        [ -z "$tokens" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        off=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*server_tokens[[:space:]]+off' "$f" 2>/dev/null)
            [ -n "$l" ] && off="$off
$f: $l"
        done
        evidence="$evidence
[Nginx] server_tokens off 검색: ${off:-없음(기본값 on - 버전 정보 노출)}"
        [ -z "$off" ] && violations="$violations nginx"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        server_attr=""
        [ -f "$f" ] && server_attr=$(strip_xml_comments "$f" | grep -nE 'Connector[^>]*server="')
        evidence="$evidence
[Tomcat] Connector server= 속성: ${server_attr:-없음(기본 배너 노출)}"
        [ -z "$server_attr" ] && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="응답 헤더에 서버 정보가 노출되는 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="응답 헤더의 서버 정보 노출이 제한되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}
