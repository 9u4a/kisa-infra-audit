# WEB-08 (하) 웹 서비스 파일 업로드 및 다운로드 용량 제한 — 조치 [fix: auto]
# 가이드 권고에 맞춰 넉넉한 상한값(10MB)을 기본값으로 설정한다 - 실제 업무에 필요한 값은
# 조직마다 다를 수 있지만, "제한이 전혀 없는" 상태보다 안전한 값이라 U-28류 문제는 아니다.
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*LimitRequestBody' "$f" 2>/dev/null && hit=1
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            printf '\n# KISA WEB-08: 업로드 용량 제한(10MB)\nLimitRequestBody 10485760\n' >> "$conf"
            applied="$applied apache($conf)"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        if [ -f "$f" ]; then
            hit=$(grep -E 'maxPostSize|maxSwallowSize' "$f" 2>/dev/null)
            if [ -z "$hit" ]; then
                fix_backup "$f"
                # Connector 태그는 속성이 여러 줄에 걸쳐 있는 경우가 흔해(실제 tomcat:10 기본
                # server.xml 로 실기 확인) 닫는 ">" 를 찾는 sed 대신, "<Connector" 문자열이
                # 있는 그 줄에서 바로 뒤에 속성을 삽입한다(같은 줄에 port="8080" 도 함께 있음).
                awk '
                    !done && /<Connector[^>]*port="8080"/ { sub(/<Connector/, "<Connector maxPostSize=\"10485760\""); done=1 }
                    { print }
                ' "$f" > "$f.kisa_tmp" && mv "$f.kisa_tmp" "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="업로드 용량 제한(10MB)을 설정함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="제한이 필요한 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
