# WEB-21 (중) HTTP 리디렉션
# 판단 기준(가이드 원문): 양호 = HTTP 접근 시 HTTPS Redirection 활성화 / 취약 = 비활성화
# 대상: Apache, Nginx, IIS, WebtoB
# 리다이렉트 대상이 https:// 인 것만 인정한다 - 예전에는 "Redirect permanent / http://다른곳" 도 GOOD 이었다
# (진단 검수 WEB-R10). Apache: Redirect/RedirectMatch/RedirectPermanent/RedirectTemp 또는 RewriteRule 의 대상이 https://,
# Nginx: return 301/302/307/308 https://… 또는 rewrite … https://….
# 1.5.0 A20: 평문(HTTP)을 받는 모든 범위에 리다이렉트가 있어야 GOOD - 예전에는 파일 어딘가에 한 줄이라도 있으면 GOOD 이었다.
#   Apache: SSL 이 아닌 <VirtualHost> 마다 자기 리다이렉트 또는 서버 전역 Redirect(VirtualHost 가 물려받음 - RewriteRule 은
#           RewriteOptions Inherit 일 때만), VirtualHost 가 받지 않는 평문 Listen 포트가 있으면 서버 전역(main)에도 필요.
#   Nginx : ssl 이 아닌 listen(listen 이 없으면 기본 80)을 가진 server 블록마다 그 블록(또는 안의 location)에 리다이렉트.

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            res=$(apache_https_redirect_scopes)
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*(Redirect(Match|Permanent|Temp)?[[:space:]][^#]*[[:space:]]"?https://|RewriteRule[[:space:]][^#]*[[:space:]]"?https://)' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            bad=$(printf '%s\n' "$res" | awk -F '\t' '$1 == "BAD" { print $2 }')
            evidence="$evidence
[Apache] HTTPS 리다이렉트 설정 검색: $(printf '%s' "${hit:-없음}" | web_mask_url_secrets)
[Apache] 범위별 판정:
$(printf '%s\n' "$res" | tr '\t' ' ')"
            if [ -z "$res" ]; then
                errors="$errors apache(VirtualHost 범위 해석 실패)"
            elif [ -n "$bad" ]; then
                violations="$violations apache(리다이렉트 없음: $(printf '%s\n' "$bad" | head -n 3 | tr '\n' ';' | sed 's/;$//'))"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            res=$(nginx_https_redirect_servers)
            bad=$(printf '%s\n' "$res" | awk -F '\t' '$1 == "BAD" { print $2 }')
            evidence="$evidence
[Nginx] server 블록별 HTTP->HTTPS 리다이렉트(return 30x https / rewrite https):
$(printf '%s\n' "${res:-server 블록 없음}" | tr '\t' ' ' | web_mask_url_secrets)"
            if [ -z "$res" ] || [ -n "$bad" ]; then
                violations="$violations nginx(리다이렉트 없음: $(printf '%s\n' "${bad:-server 블록 없음}" | head -n 3 | tr '\n' ';' | sed 's/;$//'))"
            fi
        fi
    esac

    web_finish "HTTP->HTTPS 리다이렉션이 비활성화된 엔진" "HTTP->HTTPS 리다이렉션이 활성화되어 있음"
}
