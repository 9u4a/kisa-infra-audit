# WEB-23 (중) LDAP 알고리즘 적절하게 구성
# 판단 기준(가이드 원문): 양호 = LDAP 인증 시 SHA-256 이상 다이제스트 사용 / 취약 = 그 이하
# 대상: Tomcat 전용

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            errors=""
            if ! web_load_tomcat_conf server.xml; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="server.xml 을 확인하지 못함:$errors"; CHECK_EVIDENCE=""
                return
            fi
            f=$TC_FILE
            # 1.5.0 A23: Tomcat 8+ 는 Realm 의 digest 속성 대신 <CredentialHandler algorithm="..."/> 를 쓴다 - 예전에는 digest 만 봐
            # CredentialHandler 의 MD5 가 "설정 없음(NA)" 이 됐다. 첫 값만 보던 것도 모든 값을 보도록 바꿨다(하나라도 약하면 VULN).
            algs=$(strip_xml_comments "$f" | tr '\n\r' '  ' | \
                grep -oE "(<Realm|<CredentialHandler)([[:space:]]+[A-Za-z_:.-]+[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*'))*" | \
                while IFS= read -r e; do
                    case "$e" in
                        "<Realm"*) v=$(xml_attr "$e" digest); [ -n "$v" ] && printf 'Realm digest=%s\n' "$v" ;;
                        *) v=$(xml_attr "$e" algorithm); [ -n "$v" ] && printf 'CredentialHandler algorithm=%s\n' "$v" ;;
                    esac
                done)
            if [ -z "$algs" ]; then
                CHECK_STATUS="NA"; CHECK_DETAIL="LDAP Realm 다이제스트(digest 속성·CredentialHandler algorithm)가 설정되어 있지 않음"
                CHECK_EVIDENCE="$f 에 digest/CredentialHandler algorithm 없음"
                return
            fi
            CHECK_EVIDENCE="$algs"
            weak=$(printf '%s\n' "$algs" | grep -viE 'SHA-?(256|384|512)|SHA3-')
            if [ -z "$weak" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="LDAP 다이제스트 알고리즘이 SHA-256 이상으로 설정됨"
            else
                CHECK_STATUS="VULN"; CHECK_DETAIL="LDAP 다이제스트 알고리즘이 취약함(SHA-256 미만): $(printf '%s' "$weak" | tr '\n' ' ')"
            fi
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}
