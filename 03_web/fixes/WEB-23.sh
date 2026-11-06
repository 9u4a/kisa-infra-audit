# WEB-23 (중) LDAP 알고리즘 적절하게 구성 — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 변경: Tomcat server.xml 의 Realm digest 속성·CredentialHandler algorithm 중 약한 값(MD5/SHA-1 등) → "SHA-256"
# 대상: Tomcat 전용
run_fix() {
    detect_web_engines
    case " $WEB_ENGINES " in *" tomcat "*) : ;; *)
        FIX_STATUS="NA"; FIX_DETAIL="Tomcat 이 감지되지 않음"; FIX_EVIDENCE=""
        return
        ;;
    esac
    # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
    tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
    f="$tcdir/server.xml"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    # 진단(checks/WEB-23.sh)과 같은 대상: Realm digest 속성 + <CredentialHandler algorithm>(Tomcat 8+, 1.5.0 A23). 주석 밖의
    # 약한 MessageDigest 이름(MD2/MD5/SHA/SHA-1/SHA-224)만 SHA-256 으로 바꾼다. PBKDF2WithHmacSHA1 같은 SecretKey 알고리즘은
    # 반복 횟수·키 길이와 함께 정해야 해 자동으로 바꾸지 않는다(재검증 VULN → 원복, 수동 조치).
    weak_re="(MD2|MD5|SHA|SHA-?1|SHA-?224)"
    found=$(strip_xml_comments "$f" | grep -oiE "(^|[[:space:]])(digest|algorithm)[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')")
    if [ -z "$found" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="LDAP Realm 다이제스트(digest 속성·CredentialHandler algorithm)가 설정되어 있지 않음"; FIX_EVIDENCE=""
        return
    fi
    weak=$(printf '%s\n' "$found" | grep -iE "=[[:space:]]*[\"']${weak_re}[\"']")
    if [ -z "$weak" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="바꿀 약한 MessageDigest 알고리즘이 없음(이미 SHA-256 이상이거나 수동 조치 대상)"; FIX_EVIDENCE="$found"
        return
    fi
    fix_backup "$f"
    fix_sed_inplace "$f" -E "s/((^|[[:space:]])(digest|algorithm)[[:space:]]*=[[:space:]]*)[\"']${weak_re}[\"']/\\1\"SHA-256\"/gI"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="LDAP Realm 다이제스트 알고리즘을 SHA-256 으로 설정함"
    FIX_EVIDENCE="변경 전:$(printf '%s' "$weak" | tr '\n' ' ')"
}
