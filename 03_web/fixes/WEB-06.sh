# WEB-06 (상) 웹 서비스 상위 디렉터리 접근 제한 설정 — 조치 [fix: confirm]
# 대상: Tomcat 전용(checks/WEB-06.sh 참고 — Apache/Nginx 는 자동 판정 자체가 MANUAL 이라 VULN 을
# 내지 않으므로 fix 대상이 아님).
run_fix() {
    detect_web_engines
    case " $WEB_ENGINES " in *" tomcat "*) : ;; *)
        FIX_STATUS="NA"; FIX_DETAIL="Tomcat 이 감지되지 않음"; FIX_EVIDENCE=""
        return
        ;;
    esac
    home=$(tomcat_home)
    f="$home/conf/server.xml"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    hit=$(strip_xml_comments "$f" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true')
    if [ -z "$hit" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="allowLinking=true 설정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$f"
    sed -i -E 's/allowLinking[[:space:]]*=[[:space:]]*"true"/allowLinking="false"/I' "$f"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Tomcat Context allowLinking 을 false 로 설정함"
    FIX_EVIDENCE="$hit"
}
