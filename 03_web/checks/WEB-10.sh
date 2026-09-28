# WEB-10 (상) 불필요한 프록시 설정 제한
# 판단 기준(가이드 원문): 양호 = 불필요한 Proxy 설정을 제한한 경우 / 취약 = 제한하지 않은 경우
# "불필요 여부"는 업무 판단이 필요하므로, Proxy 관련 설정 존재 시 MANUAL 로 안내한다.

run_check() {
    detect_web_engines
    manuals=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*(ProxyPass|ProxyRequests[[:space:]]+On)' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Apache] Proxy 설정: ${hit:-없음}"
        [ -n "$hit" ] && manuals="$manuals apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*proxy_pass' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Nginx] proxy_pass 설정: ${hit:-없음}"
        [ -n "$hit" ] && manuals="$manuals nginx"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        hit=""
        [ -f "$f" ] && hit=$(strip_xml_comments "$f" | grep -nE 'proxyName|proxyPort')
        evidence="$evidence
[Tomcat] Connector proxyName/proxyPort: ${hit:-없음}"
        [ -n "$hit" ] && manuals="$manuals tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$manuals" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="Proxy 설정이 존재함 — 업무상 필요한 설정인지 수동 확인 필요:$manuals"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="Proxy 관련 설정이 발견되지 않음"
    fi
    CHECK_EVIDENCE="$evidence"
}
