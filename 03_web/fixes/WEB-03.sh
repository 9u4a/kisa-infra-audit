# WEB-03 (상) 비밀번호 파일 권한 관리 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    case " $WEB_ENGINES " in *" tomcat "*) : ;; *)
        FIX_STATUS="NA"; FIX_DETAIL="Tomcat 이 감지되지 않음"; FIX_EVIDENCE=""
        return
        ;;
    esac
    home=$(tomcat_home)
    f="$home/conf/tomcat-users.xml"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    owner=$(stat -c '%U' "$f" 2>/dev/null)
    case "$owner" in
        root|tomcat) : ;;
        *) owner="tomcat" ;;
    esac
    fix_set_owner_perm "$f" "$owner" 600
}
