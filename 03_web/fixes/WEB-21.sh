# WEB-21 (중) HTTP 리디렉션 — 조치 [fix: confirm]
# WEB-20(SSL/TLS 활성화)이 선행되어 있어야 한다(HTTPS 로 보낼 곳이 없으면 리다이렉트 자체가
# 서비스 중단을 일으킴). Apache 는 ServerName 값을 이용해 안전하게 리다이렉트 대상을 구성할
# 수 있지만, Nginx 는 리다이렉트를 넣어야 할 정확한 server{} 블록을 텍스트 치환만으로 안전하게
# 특정하기 어려워(잘못 넣으면 설정 자체가 깨질 위험) 자동 조치 대상에서 제외하고 수동 안내로
# 남긴다(둘 다 U-28류의 "안전하게 자동화할 수 없음" 문제와 같은 결의 판단).
run_fix() {
    detect_web_engines
    applied=""
    manual_only=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        ssl_on=""
        redirect_on=""
        server_name=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*SSLEngine[[:space:]]+on' "$f" 2>/dev/null && ssl_on=1
            grep -qE '^[^#]*(Redirect[[:space:]]+(permanent|301)|RewriteRule[^#]*https)' "$f" 2>/dev/null && redirect_on=1
            [ -z "$server_name" ] && server_name=$(grep -E '^[^#]*ServerName[[:space:]]' "$f" 2>/dev/null | tail -n1 | sed -E 's/^[[:space:]]*ServerName[[:space:]]+//')
        done
        if [ -z "$redirect_on" ]; then
            if [ -n "$ssl_on" ] && [ -n "$server_name" ] && [ -f "$conf" ]; then
                fix_backup "$conf"
                printf '\n# KISA WEB-21: HTTP -> HTTPS 리다이렉트\nRedirect permanent / https://%s/\n' "$server_name" >> "$conf"
                applied="$applied apache($conf, target=https://$server_name/)"
            else
                manual_only="$manual_only apache(SSL 미설정 또는 ServerName 을 찾지 못해 리다이렉트 대상을 안전하게 구성 불가 - 먼저 SSL/TLS 를 구성하고 ServerName 을 지정할 것)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*return[[:space:]]+30[12][[:space:]]+https' "$f" 2>/dev/null && hit=1
        done
        [ -z "$hit" ] && manual_only="$manual_only nginx(정확한 server{} 블록을 텍스트 치환만으로 안전하게 특정할 수 없어 자동 조치 미지원 - listen 80 서버 블록에 'return 301 https://\$host\$request_uri;' 를 수동 추가할 것)"
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="HTTP->HTTPS 리다이렉트를 설정함:$applied${manual_only:+ / 수동 조치 필요:$manual_only}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_only" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요:$manual_only"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="리다이렉트가 필요한 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
