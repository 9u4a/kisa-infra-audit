# WEB-19 (중) 웹 서비스 SSI(Server Side Includes) 사용 제한 — 조치 [fix: auto]
# Tomcat 의 SSI 서블릿/필터 매핑은 web.xml 안에서 여러 줄에 걸친 XML 블록이라 안전하게
# 자동 제거하기 어려워(잘못 잘라내면 XML 자체가 깨질 위험) 이 엔진만 수동 조치로 남긴다.
run_fix() {
    detect_web_engines
    applied=""
    manual_only=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*Options[^#]*\bIncludes\b' "$f" 2>/dev/null || continue
            grep -qE '^[^#]*Options[^#]*\-Includes\b' "$f" 2>/dev/null && continue
            fix_backup "$f"
            sed -i -E '/^[^#]*Options[^#]*Includes/{ s/\bIncludes\b/-Includes/ }' "$f"
            applied="$applied apache($f)"
        done
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*ssi[[:space:]]+on' "$f" 2>/dev/null || continue
            fix_backup "$f"
            sed -i -E 's/^([[:space:]]*)ssi[[:space:]]+on/\1ssi off/' "$f"
            applied="$applied nginx($f)"
        done
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        if [ -f "$f" ]; then
            hit=$(strip_xml_comments "$f" | grep -E 'SSIServlet|SSIFilter')
            [ -n "$hit" ] && manual_only="$manual_only tomcat($f: SSIServlet/SSIFilter 매핑을 수동으로 제거 필요 - 다중 라인 XML 블록이라 자동 제거 미지원)"
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="SSI 사용을 제한함:$applied${manual_only:+ / 수동 조치 필요:$manual_only}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_only" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요:$manual_only"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="SSI 가 활성화된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
