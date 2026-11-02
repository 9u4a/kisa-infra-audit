# WEB-10 (상) 불필요한 프록시 설정 제한
# 판단 기준(가이드 원문): 양호 = 불필요한 Proxy 설정을 제한한 경우 / 취약 = 제한하지 않은 경우
# "불필요 여부"는 업무 판단이 필요하므로, Proxy 관련 설정 존재 시 MANUAL 로 안내한다. 단 Apache 정방향 프록시
# (ProxyRequests On)는 VULN(1.4.1, guide.json deviation).
# Tomcat Connector 증적의 keystorePass 등 비밀번호류 속성은 가린다(S5, 진단 검수 WEB-R9). Apache/Nginx 프록시·리다이렉트 줄의 URL 사용자 정보·토큰은 web_mask_url_secrets 로 가린다(1.3.3).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""; fwd=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*ProxyPass' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
                l=$(grep -niE '^[[:space:]]*ProxyRequests[[:space:]]+On' "$f" 2>/dev/null)
                [ -n "$l" ] && fwd="$fwd
$f: $l"
            done
            evidence="$evidence
[Apache] 역방향 Proxy(ProxyPass): $(printf '%s' "${hit:-없음}" | web_mask_url_secrets)
[Apache] 정방향 Proxy(ProxyRequests On): ${fwd:-없음}"
            # 1.4.1(Q-03): ProxyRequests On 은 누구나 서버를 경유지로 쓰는 정방향(오픈) 프록시라 업무 필요와 무관하게
            # 가이드의 "불필요한 Proxy" 로 본다 - VULN. 역방향(ProxyPass)만 있으면 업무 필요 여부를 알 수 없어 MANUAL.
            if [ -n "$fwd" ]; then violations="$violations apache(ProxyRequests On)"
            elif [ -n "$hit" ]; then manuals="$manuals apache"; fi
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
