# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*ServerTokens[[:space:]]+Prod' "$f" 2>/dev/null && hit=1
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            printf '\n# KISA WEB-16: 서버 정보 노출 제한\nServerTokens Prod\nServerSignature Off\n' >> "$conf"
            applied="$applied apache($conf)"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*server_tokens[[:space:]]+off' "$f" 2>/dev/null && hit=1
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            sed -i "1i server_tokens off;" "$conf"
            applied="$applied nginx($conf)"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        if [ -f "$f" ]; then
            hit=$(strip_xml_comments "$f" | grep -nE 'Connector[^>]*server="')
            if [ -z "$hit" ]; then
                fix_backup "$f"
                # check(WEB-16)도 grep 이 "Connector"와 "server=" 가 같은 줄에 있는지로
                # 판정하므로(멀티라인 미지원), 닫는 ">" 를 찾지 않고 "<Connector" 바로 뒤에
                # 삽입한다 - 실제 tomcat:10 기본 server.xml 처럼 속성이 여러 줄에 걸친
                # Connector 에서도 안전하게 동작한다(실기 테스트로 발견한 버그 수정).
                awk '
                    !done && /<Connector[^>]*port="8080"/ { sub(/<Connector/, "<Connector server=\"WebServer\""); done=1 }
                    { print }
                ' "$f" > "$f.kisa_tmp" && mv "$f.kisa_tmp" "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="응답 헤더의 서버 정보 노출을 제한함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="서버 정보를 노출하는 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
