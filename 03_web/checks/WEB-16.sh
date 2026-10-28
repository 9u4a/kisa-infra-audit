# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한
# 판단 기준(가이드 원문): 양호 = HTTP 응답 헤더에서 웹 서버 정보가 노출되지 않음
#                        취약 = 노출됨
# Apache ServerTokens 는 마지막 값이 적용된다 - 실제 로드 순서상 마지막 값이 Prod(ProductOnly) 일 때만 GOOD
# (Debian 은 conf-enabled/security.conf 의 "ServerTokens OS" 가 나중에 읽힌다 - 진단 검수 WEB-R11).
# Nginx 는 server_tokens off 가 있어도 다른 블록의 on/build 가 있으면 그 범위에서 노출되므로 VULN.

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            last=$(apache_last_directive ServerTokens)
            val=$(printf '%s' "$last" | cut -f1 | tr 'A-Z' 'a-z')
            shown="없음(기본값 Full - 상세 정보 노출)"
            [ -n "$last" ] && shown=$(printf '%s' "$last" | cut -f2)
            evidence="$evidence
[Apache] 적용되는(마지막) ServerTokens: $shown"
            case "$val" in
                prod|productonly) : ;;
                *) violations="$violations apache" ;;
            esac
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            off=""; on=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*server_tokens[[:space:]]+off' "$f" 2>/dev/null)
                [ -n "$l" ] && off="$off
$f: $l"
                l=$(grep -nE '^[^#]*server_tokens[[:space:]]+(on|build)' "$f" 2>/dev/null)
                [ -n "$l" ] && on="$on
$f: $l"
            done
            evidence="$evidence
[Nginx] server_tokens off 검색: ${off:-없음(기본값 on - 버전 정보 노출)}${on:+
[Nginx] server_tokens on/build 검색: $on}"
            { [ -z "$off" ] || [ -n "$on" ]; } && violations="$violations nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            server_attr=$(strip_xml_comments "$TC_FILE" | grep -nE 'Connector[^>]*server="' | web_mask_xml_secrets)
            evidence="$evidence
[Tomcat] Connector server= 속성: ${server_attr:-없음(기본 배너 노출)}"
            [ -z "$server_attr" ] && violations="$violations tomcat"
        fi
    esac

    web_finish "응답 헤더에 서버 정보가 노출되는 엔진" "응답 헤더의 서버 정보 노출이 제한되어 있음"
}
