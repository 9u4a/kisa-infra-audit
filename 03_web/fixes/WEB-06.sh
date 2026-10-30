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
    # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
    tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
    # 진단과 같은 대상: server.xml + conf/context.xml(Tomcat 8.5+ 는 <Resources allowLinking="true"/> 를 context.xml 에
    # 두는 경우가 많다 - 예전에는 server.xml 만 고쳐 context.xml 의 설정이 남아 재검증 VULN → 원복으로 끝났다, 커버리지 검수 WEB-C4)
    if [ ! -f "$tcdir/server.xml" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$tcdir/server.xml 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    hits=""
    for f in "$tcdir/server.xml" "$tcdir/context.xml"; do
        [ -f "$f" ] || continue
        hit=$(strip_xml_comments "$f" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true')
        [ -n "$hit" ] || continue
        fix_backup "$f"
        fix_sed_inplace "$f" -E 's/allowLinking[[:space:]]*=[[:space:]]*"true"/allowLinking="false"/I'
        hits="$hits
$f: $(printf '%s' "$hit" | web_mask_xml_secrets)"
    done
    if [ -z "$hits" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="allowLinking=true 설정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Tomcat allowLinking 을 false 로 설정함(server.xml/context.xml)"
    FIX_EVIDENCE="$hits"
}
