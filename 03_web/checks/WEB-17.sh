# WEB-17 (중) 웹 서비스 가상 디렉로리 삭제
# 판단 기준(가이드 원문): 양호 = 불필요한 가상 디렉터리가 없음 / 취약 = 존재함
# 대상: Apache, Tomcat, Nginx, WebtoB. "불필요 여부"는 업무 판단이 필요해 목록을 근거로 MANUAL.

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*(Script)?Alias(Match)?[[:space:]]+/' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] Alias 목록: ${hit:-없음}"
            [ -n "$hit" ] && manuals="$manuals apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*alias[[:space:]]+' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] alias 목록: ${hit:-없음}"
            [ -n "$hit" ] && manuals="$manuals nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -nE '<Context[^>]*path="/[^"]' | web_mask_xml_secrets)
            evidence="$evidence
[Tomcat] Context path 목록: ${hit:-없음}"
            [ -n "$hit" ] && manuals="$manuals tomcat"
        fi
    esac

    web_finish "불필요한 가상 디렉터리가 있는 엔진" "가상 디렉터리(Alias/Context)가 발견되지 않음" "가상 디렉터리가 존재함 — 불필요 여부 수동 확인 필요"
}
