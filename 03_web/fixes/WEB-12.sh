# WEB-12 (중) 웹 서비스 링크 사용 금지 — 조치 [fix: confirm]
# 심볼릭 링크로 실제 서비스 콘텐츠가 구성된 경우 이 조치로 서비스가 깨질 수 있다는 점이
# 가이드 '조치 시 영향'에 명시되어 있어 confirm 등급이다(checks/WEB-12.sh 참고).
run_fix() {
    detect_web_engines
    applied=""
    manual_only=""

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
        # checks/WEB-12.sh: Options 지시자가 하나도 없으면 Apache 2.4 기본값(FollowSymLinks)이 적용돼 VULN 이다.
        # 어느 <Directory> 에 무엇을 넣을지는 서비스 구성에 달려 있어 자동으로 넣지 않고 수동 조치로 안내한다.
        any_opt=""
        for f in $files; do
            [ -f "$f" ] || continue
            awk '{ t = $0; sub(/^[ \t]+/, "", t); split(t, a, /[ \t]+/); if (tolower(a[1]) == "options") { f = 1; exit } } END { exit !f }' "$f" 2>/dev/null && { any_opt=1; break; }
        done
        [ -z "$any_opt" ] && manual_only="$manual_only apache(Options 지시자가 없어 기본값 FollowSymLinks 가 적용됨 - 웹 루트 <Directory> 에 'Options -FollowSymLinks' 등 수동 추가)"
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
                manual_only="$manual_only nginx($conf 에서 http 블록을 찾지 못해 자동 조치 불가 - http/server 블록에 'disable_symlinks on;' 수동 추가)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
        tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
        f="$tcdir/server.xml"
        if [ -f "$f" ]; then
            hit=$(strip_xml_comments "$f" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true')
            if [ -n "$hit" ]; then
                fix_backup "$f"
                fix_sed_inplace "$f" -E 's/allowLinking[[:space:]]*=[[:space:]]*"true"/allowLinking="false"/I'
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="심볼릭 링크 사용을 제한함:$applied${manual_only:+ / 수동 조치 필요: $manual_only}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_only" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요: $manual_only"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="심볼릭 링크가 허용된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
