# WEB-23 (중) LDAP 알고리즘 적절하게 구성 — 조치 [fix: auto]
# 대상: Tomcat 전용
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
    digest=$(strip_xml_comments "$f" | grep -oE 'digest="[^"]*"' | head -n1)
    if [ -z "$digest" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="LDAP Realm(digest 속성)이 설정되어 있지 않음"; FIX_EVIDENCE=""
        return
    fi
    if printf '%s' "$digest" | grep -qiE 'SHA-256|SHA-512|SHA256|SHA512'; then
        FIX_STATUS="NA"; FIX_DETAIL="이미 SHA-256 이상으로 설정되어 있음"; FIX_EVIDENCE="$digest"
        return
    fi
    fix_backup "$f"
    sed -i -E 's/digest="[^"]*"/digest="SHA-256"/' "$f"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="LDAP Realm digest 알고리즘을 SHA-256 으로 설정함"
    FIX_EVIDENCE="변경 전: $digest"
}
