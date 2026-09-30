# WEB-22 (하) 에러 페이지 관리 — 조치 [fix: auto]
# 별도 에러 페이지 파일을 새로 만들지 않고, 정보 노출이 없는 일반 안내 문구를 인라인으로
# 반환하도록 설정한다(가이드 취지: "에러 페이지가 별도로 지정됨").
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*ErrorDocument' "$f" 2>/dev/null && hit=1
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            printf '\n# KISA WEB-22: 에러 페이지 지정\nErrorDocument 404 "페이지를 찾을 수 없습니다."\nErrorDocument 500 "일시적인 오류가 발생했습니다."\n' >> "$conf"
            applied="$applied apache($conf)"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*error_page' "$f" 2>/dev/null && hit=1
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            printf '\n# KISA WEB-22: 에러 페이지 지정\nerror_page 404 /404.html;\nerror_page 500 502 503 504 /50x.html;\n' >> "$conf"
            applied="$applied nginx($conf)"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        if [ -f "$f" ]; then
            cnt=$(strip_xml_comments "$f" | grep -c '<error-page>')
            if [ "$cnt" -eq 0 ]; then
                fix_backup "$f"
                awk '
                    /<\/web-app>/ && !done {
                        print "  <error-page>"
                        print "    <error-code>404</error-code>"
                        print "    <location>/404.html</location>"
                        print "  </error-page>"
                        print "  <error-page>"
                        print "    <error-code>500</error-code>"
                        print "    <location>/500.html</location>"
                        print "  </error-page>"
                        done=1
                    }
                    { print }
                ' "$f" > "$f.kisa_tmp" && mv "$f.kisa_tmp" "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="에러 페이지를 지정함:$applied (실제 /404.html, /50x.html 등 파일이 없으면 컨테이너 기본 오류로 대체될 수 있음 - 페이지 내용 자체는 별도 준비 필요)"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="에러 페이지 지정이 필요한 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
