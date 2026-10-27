# WEB-12 (중) 웹 서비스 링크 사용 금지 — 조치 [fix: confirm]
# 심볼릭 링크로 실제 서비스 콘텐츠가 구성된 경우 이 조치로 서비스가 깨질 수 있다는 점이
# 가이드 '조치 시 영향'에 명시되어 있어 confirm 등급이다(checks/WEB-12.sh 참고).
run_fix() {
    detect_web_engines
    applied=""
    manual_nginx=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            apache_options_enabled "$f" FollowSymLinks || continue
            fix_backup "$f"
            # +/- 혼용 문법 오류를 만들지 않도록 토큰 단위로 재구성(lib/common.sh apache_options_disable)
            apache_options_disable "$f" FollowSymLinks && applied="$applied apache($f)"
        done
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*disable_symlinks[[:space:]]+on' "$f" 2>/dev/null && hit=1
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            # disable_symlinks 는 http/server/location 컨텍스트 전용 - 파일 끝(main)에 붙이면 nginx 기동 실패
            if nginx_http_insert "$conf" "disable_symlinks on;"; then
                applied="$applied nginx($conf)"
            else
                manual_nginx="nginx($conf 에서 http 블록을 찾지 못해 자동 조치 불가 - http/server 블록에 'disable_symlinks on;' 수동 추가)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        if [ -f "$f" ]; then
            hit=$(strip_xml_comments "$f" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true')
            if [ -n "$hit" ]; then
                fix_backup "$f"
                sed -i -E 's/allowLinking[[:space:]]*=[[:space:]]*"true"/allowLinking="false"/I' "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="심볼릭 링크 사용을 제한함:$applied${manual_nginx:+ / 수동 조치 필요: $manual_nginx}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_nginx" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요: $manual_nginx"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="심볼릭 링크가 허용된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
