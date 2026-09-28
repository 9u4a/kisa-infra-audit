# WEB-23 (중) LDAP 알고리즘 적절하게 구성
# 판단 기준(가이드 원문): 양호 = LDAP 인증 시 SHA-256 이상 다이제스트 사용 / 취약 = 그 이하
# 대상: Tomcat 전용

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            home=$(tomcat_home)
            f="$home/conf/server.xml"
            if [ ! -f "$f" ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="$f 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
                return
            fi
            digest=$(strip_xml_comments "$f" | grep -oE 'digest="[^"]*"' | head -n1)
            if [ -z "$digest" ]; then
                CHECK_STATUS="NA"; CHECK_DETAIL="LDAP Realm(digest 속성)이 설정되어 있지 않음"; CHECK_EVIDENCE="$f 에 digest 속성 없음"
                return
            fi
            CHECK_EVIDENCE="$digest"
            if printf '%s' "$digest" | grep -qiE 'SHA-256|SHA-512|SHA256|SHA512'; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="LDAP 다이제스트 알고리즘이 SHA-256 이상으로 설정됨"
            else
                CHECK_STATUS="VULN"; CHECK_DETAIL="LDAP 다이제스트 알고리즘이 취약함(SHA-256 미만)"
            fi
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}
