# WEB-13 (상) 웹 서비스 설정 파일 노출 제한 — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# checks/WEB-13.sh 와 같은 대상: server.xml·context.xml 중 <Resource> 가 있는 파일을 600 으로(소유자는 허용 목록이면 유지).
run_fix() {
    detect_web_engines
    case " $WEB_ENGINES " in *" tomcat "*) : ;; *)
        FIX_STATUS="NA"; FIX_DETAIL="Tomcat 이 감지되지 않음"; FIX_EVIDENCE=""
        return
        ;;
    esac
    errors=""
    if ! web_load_tomcat_conf server.xml; then
        FIX_STATUS="ERROR"; FIX_DETAIL="server.xml 을 확인하지 못함:$errors"; FIX_EVIDENCE=""
        return
    fi
    files=""
    for f in "$TC_FILE" "$(dirname "$TC_FILE")/context.xml"; do
        [ -r "$f" ] || continue
        [ "$(strip_xml_comments "$f" | grep -cE '<Resource([[:space:]/>]|$)')" -gt 0 ] && files="$files $f"
    done
    if [ -z "$files" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="DB 연결 리소스가 설정된 파일이 없음"; FIX_EVIDENCE=""
        return
    fi
    st=""; det=""
    for f in $files; do
        owner=$(stat -L -c '%U' "$f" 2>/dev/null)
        case "$owner" in
            root|tomcat|tomcat8|tomcat9|tomcat10) : ;;
            *) owner="tomcat" ;;
        esac
        fix_set_owner_perm "$f" "$owner" 600
        det="$det / $FIX_DETAIL"
        [ "$FIX_STATUS" = "APPLIED" ] && [ -z "$st" ] && st="APPLIED"
        [ "$FIX_STATUS" = "ERROR" ] && st="ERROR"
    done
    FIX_STATUS=${st:-$FIX_STATUS}
    FIX_DETAIL=${det# / }
    # shellcheck disable=SC2086
    FIX_EVIDENCE=$(ls -l $files 2>/dev/null)
}
