# WEB-21 (중) HTTP 리디렉션 — 조치 [fix: confirm]
# 변경: Apache(SSLEngine on·ServerName 있을 때): 메인 설정에 <If HTTPS != on> Redirect permanent / https://<ServerName>/ 추가, Nginx 는 수동
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
            [ -z "$server_name" ] && server_name=$(grep -E '^[^#]*ServerName[[:space:]]' "$f" 2>/dev/null | tail -n1 | sed -E 's/^[[:space:]]*ServerName[[:space:]]+//')
        done
        # checks/WEB-21.sh 와 같은 기준(대상이 https:// 인 것만, 1.5.0 A20 범위별): 서버 전역 Redirect 가 있으면 모든 VirtualHost 가
        # 물려받으므로, 진단이 리다이렉트 없는 범위를 찾았고 서버 전역 Redirect 가 없을 때만 전역 리다이렉트를 넣는다.
        # (VirtualHost 하나에만 리다이렉트가 있던 경우에도 나머지 VirtualHost 를 위해 전역에 넣는다)
        apache_https_redirect_scopes | grep -q '^BAD' || redirect_on=1
        if [ -z "$redirect_on" ]; then
            if [ -n "$ssl_on" ] && [ -n "$server_name" ] && [ -f "$conf" ]; then
                fix_backup "$conf"
                # 서버 전역 Redirect 는 SSL(443) 가상호스트에도 상속돼 HTTPS 요청까지 다시 리다이렉트하는
                # 무한 루프가 난다 - HTTPS 가 아닐 때만 동작하도록 <If> 로 감싼다(Apache 2.4 core,
                # mod_alias 문서의 <If> + Redirect 예시와 같은 형식).
                printf '\n# KISA WEB-21: HTTP -> HTTPS 리다이렉트(평문 요청에만 적용)\n<If "%%{HTTPS} != '"'on'"'">\n    Redirect permanent / https://%s/\n</If>\n' "$server_name" >> "$conf"
                applied="$applied apache($conf, target=https://$server_name/)"
            else
                manual_only="$manual_only apache(SSL 미설정 또는 ServerName 을 찾지 못해 리다이렉트 대상을 안전하게 구성 불가 - 먼저 SSL/TLS 를 구성하고 ServerName 을 지정할 것)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        # checks/WEB-21.sh 와 같은 기준(server 블록별, 1.5.0 A20): 리다이렉트 없는 평문 server 블록이 하나라도 있으면 수동 안내
        bad=$(nginx_https_redirect_servers | awk -F '\t' '$1 == "BAD" { print $2 }' | head -n 3 | tr '\n' ';' | sed 's/;$//')
        [ -n "$bad" ] && manual_only="$manual_only nginx(정확한 server{} 블록을 텍스트 치환만으로 안전하게 특정할 수 없어 자동 조치 미지원 - 리다이렉트 없는 server 블록($bad)에 'return 301 https://\$host\$request_uri;' 를 수동 추가할 것)"
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
