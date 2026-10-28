# WEB-20 (상) SSL/TLS 활성화
# 판단 기준(가이드 원문): 양호 = SSL/TLS 활성화 / 취약 = 비활성화
# 대상: Apache, Nginx, IIS, WebtoB

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*SSLEngine[[:space:]]+on' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] SSLEngine on 검색: ${hit:-없음}"
            [ -z "$hit" ] && violations="$violations apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*listen[^#;]*[[:space:]]ssl([[:space:];]|$)' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] listen ... ssl 검색: ${hit:-없음}"
            [ -z "$hit" ] && violations="$violations nginx"
        fi
    esac

    web_finish "SSL/TLS 가 비활성화된 엔진" "SSL/TLS 가 활성화되어 있음"
}
