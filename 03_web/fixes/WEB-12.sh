# WEB-12 (중) 웹 서비스 링크 사용 금지 — 조치 [fix: confirm]
# 심볼릭 링크로 실제 서비스 콘텐츠가 구성된 경우 이 조치로 서비스가 깨질 수 있다는 점이
# 가이드 '조치 시 영향'에 명시되어 있어 confirm 등급이다(checks/WEB-12.sh 참고).
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*Options[^#]*\bFollowSymLinks\b' "$f" 2>/dev/null || continue
            grep -qE '^[^#]*Options[^#]*\-FollowSymLinks\b' "$f" 2>/dev/null && continue
            fix_backup "$f"
            sed -i -E '/^[^#]*Options[^#]*FollowSymLinks/{ s/\bFollowSymLinks\b/-FollowSymLinks/ }' "$f"
            applied="$applied apache($f)"
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
            printf '\n# KISA WEB-12: 심볼릭 링크 사용 금지\ndisable_symlinks on;\n' >> "$conf"
            applied="$applied nginx($conf)"
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
        FIX_DETAIL="심볼릭 링크 사용을 제한함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="심볼릭 링크가 허용된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
