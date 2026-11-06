# WEB-22 (하) 에러 페이지 관리 — 조치 [fix: auto]
# 변경: Apache: ErrorDocument 404(+ 없으면 500) 인라인 문구 추가, Nginx: error_page 50x→/50x.html·404→/404.html 추가, Tomcat: web.xml 에 404/500 <error-page> 추가
# 별도 에러 페이지 파일을 새로 만들지 않고, 정보 노출이 없는 일반 안내 문구를 인라인으로
# 반환하도록 설정한다(가이드 취지: "에러 페이지가 별도로 지정됨").
run_fix() {
    detect_web_engines
    applied=""
    manual_only=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        # 진단과 같이 404 지정 여부로 본다(1.5.0 C2 - RHEL welcome.conf 의 루트 전용 403 만 있으면 조치 대상). 500 은 없을 때만 추가
        # 1.5.0 A20: 진단은 VirtualHost 마다(자기 것 또는 서버 전역 상속) 404 를 요구한다 - 서버 전역 404 가 없으면 메인 설정 끝에
        # 넣는다(VirtualHost 하나에만 있던 경우 나머지 VirtualHost 가 이 값을 물려받는다). 500 은 서버 전역에 없을 때만 추가
        has404=""; has500=""
        apache_vhost_scopes '^errordocument[ \t]+404([ \t]|$)' | awk -F '\t' '$1 == "MAIN" && $5 == 1 { f = 1 } END { exit !f }' && has404=1
        apache_vhost_scopes '^errordocument[ \t]+500([ \t]|$)' | awk -F '\t' '$1 == "MAIN" && $5 == 1 { f = 1 } END { exit !f }' && has500=1
        if [ -z "$has404" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            # 인라인 문구는 Content-Type 이 iso-8859-1 로 나가 한글이 깨진다(실무 적용 검증 P-26) - ASCII 문구를 쓴다
            printf '\n# KISA WEB-22: 에러 페이지 지정\nErrorDocument 404 "Not Found"\n' >> "$conf"
            [ -z "$has500" ] && printf 'ErrorDocument 500 "Internal Server Error"\n' >> "$conf"
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
        # 1.5.0 A20: 진단은 server 블록마다 적용되는 error_page 에 404 를 요구한다. error_page 가 없는 server 블록은 http 블록 값을
        # 물려받으므로, http 블록에 error_page 가 하나도 없고 그런 server 블록이 있으면 http 블록에 404 를 넣는다.
        http_ep=""
        nginx_scoped_stmts | awk -F '\t' '$1 == "DIR" && $2 == "http" && $5 ~ /^error_page / { f = 1 } END { exit !f }' && http_ep=1
        bare=$(nginx_server_effective error_page "" multi | awk -F '\t' '$1 == "SRV" && $3 == "" { n++ } END { print n + 0 }')
        if [ -n "$hit" ] && [ -z "$http_ep" ] && [ "$bare" -gt 0 ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            if nginx_http_insert "$conf" "error_page 404 /404.html;"; then
                applied="$applied nginx($conf http 블록 404 - error_page 없는 server 블록 ${bare}개)"
            else
                manual_only="$manual_only nginx($conf 에서 http 블록을 찾지 못함 - error_page 없는 server 블록에 error_page 404 수동 추가)"
            fi
        fi
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            # error_page 는 http/server/location 컨텍스트 전용 - 파일 끝(main)에 붙이면 nginx 기동 실패
            if nginx_http_insert "$conf" "error_page 500 502 503 504 /50x.html;" && \
               nginx_http_insert "$conf" "error_page 404 /404.html;"; then
                applied="$applied nginx($conf)"
            else
                manual_only="$manual_only nginx($conf 에서 http 블록을 찾지 못함 - http 블록에 error_page 수동 추가)"
            fi
        elif [ -n "$hit" ]; then
            # 실무 적용 검증 P-05: error_page 가 있는 블록은 바깥 설정을 물려받지 않으므로, 404 가 없는 블록마다 그 블록의
            # 첫 error_page 줄 바로 뒤에 같은 들여쓰기로 404 를 넣는다(진단과 같은 lib/common.sh nginx_error_page_gaps).
            for f in $files; do
                [ -f "$f" ] || continue
                gaps=$(nginx_error_page_gaps "$f" | tr '\n' ' ')
                [ -n "$gaps" ] || continue
                fix_backup "$f"
                awk -v gaps=" $gaps" '
                    { print }
                    index(gaps, " " FNR " ") { ind = $0; sub(/[^ \t].*$/, "", ind); print ind "error_page 404 /404.html;" }
                ' "$f" > "$f.kisa_tmp" && fix_write_back "$f.kisa_tmp" "$f"
                applied="$applied nginx($f 404 추가)"
            done
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
        tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
        f="$tcdir/web.xml"
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
                ' "$f" > "$f.kisa_tmp" && fix_write_back "$f.kisa_tmp" "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="에러 페이지를 지정함:$applied (실제 /404.html, /50x.html 등 파일이 없으면 컨테이너 기본 오류로 대체될 수 있음 - 페이지 내용 자체는 별도 준비 필요)${manual_only:+ / 수동 조치 필요:$manual_only}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_only" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요:$manual_only"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="에러 페이지 지정이 필요한 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
