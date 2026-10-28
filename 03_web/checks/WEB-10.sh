# WEB-10 (상) 불필요한 프록시 설정 제한
# 판단 기준(가이드 원문): 양호 = 불필요한 Proxy 설정을 제한한 경우 / 취약 = 제한하지 않은 경우
# "불필요 여부"는 업무 판단이 필요하므로, Proxy 관련 설정 존재 시 MANUAL 로 안내한다.
# Tomcat Connector 증적의 keystorePass 등 비밀번호류 속성은 가린다(S5, 진단 검수 WEB-R9). Apache/Nginx 프록시·리다이렉트 줄의 URL 사용자 정보·토큰은 web_mask_url_secrets 로 가린다(1.3.3).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*(ProxyPass|ProxyRequests[[:space:]]+On)' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] Proxy 설정: $(printf '%s' "${hit:-없음}" | web_mask_url_secrets)"
            [ -n "$hit" ] && manuals="$manuals apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*proxy_pass' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] proxy_pass 설정: $(printf '%s' "${hit:-없음}" | web_mask_url_secrets)"
            [ -n "$hit" ] && manuals="$manuals nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -nE 'proxyName|proxyPort' | web_mask_xml_secrets)
            evidence="$evidence
[Tomcat] Connector proxyName/proxyPort: $(printf '%s' "${hit:-없음}" | web_mask_url_secrets)"
            [ -n "$hit" ] && manuals="$manuals tomcat"
        fi
    esac

    web_finish "불필요한 Proxy 설정이 있는 엔진" "Proxy 관련 설정이 발견되지 않음" "Proxy 설정이 존재함 — 업무상 필요한 설정인지 수동 확인 필요"
}
