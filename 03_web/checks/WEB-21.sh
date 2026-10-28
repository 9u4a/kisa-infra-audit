# WEB-21 (중) HTTP 리디렉션
# 판단 기준(가이드 원문): 양호 = HTTP 접근 시 HTTPS Redirection 활성화 / 취약 = 비활성화
# 대상: Apache, Nginx, IIS, WebtoB
# 리다이렉트 대상이 https:// 인 것만 인정한다 - 예전에는 "Redirect permanent / http://다른곳" 도 GOOD 이었다
# (진단 검수 WEB-R10). Apache: Redirect/RedirectMatch/RedirectPermanent 또는 RewriteRule 의 대상이 https://,
# Nginx: return 301/302/307/308 https://… 또는 rewrite … https://….

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*(Redirect(Match|Permanent)?[[:space:]][^#]*[[:space:]]"?https://|RewriteRule[[:space:]][^#]*[[:space:]]"?https://)' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] HTTPS 리다이렉트 설정 검색: $(printf '%s' "${hit:-없음}" | web_mask_url_secrets)"
            [ -z "$hit" ] && violations="$violations apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*(return[[:space:]]+30[1278][[:space:]]+"?https://|rewrite[[:space:]][^#;]*[[:space:]]"?https://)' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] HTTPS 리다이렉트(return 30x https / rewrite https) 검색: $(printf '%s' "${hit:-없음}" | web_mask_url_secrets)"
            [ -z "$hit" ] && violations="$violations nginx"
        fi
    esac

    web_finish "HTTP->HTTPS 리다이렉션이 비활성화된 엔진" "HTTP->HTTPS 리다이렉션이 활성화되어 있음"
}
