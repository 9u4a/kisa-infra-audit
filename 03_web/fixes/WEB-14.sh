# WEB-14 (상) 웹 서비스 경로 내 파일의 접근 통제 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        if [ -f "$conf" ]; then
            perm=$(stat -L -c '%a' "$conf" 2>/dev/null)
            if [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null; then
                owner=$(stat -L -c '%U' "$conf" 2>/dev/null)
                fix_set_owner_perm "$conf" "$owner" 750
                applied="$applied apache($conf)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        if [ -f "$conf" ]; then
            perm=$(stat -L -c '%a' "$conf" 2>/dev/null)
            if [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null; then
                owner=$(stat -L -c '%U' "$conf" 2>/dev/null)
                fix_set_owner_perm "$conf" "$owner" 750
                applied="$applied nginx($conf)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        if [ -f "$f" ]; then
            perm=$(stat -L -c '%a' "$f" 2>/dev/null)
            if [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null; then
                owner=$(stat -L -c '%U' "$f" 2>/dev/null)
                fix_set_owner_perm "$f" "$owner" 750
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="주요 설정 파일 권한을 750으로 낮춤:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="750을 초과하는 설정 파일이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
