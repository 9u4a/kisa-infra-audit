# WEB-02 (상) 취약한 비밀번호 사용 제한
# 판단 기준(가이드 원문): 양호 = 관리자 비밀번호가 암호화되어 있거나 유추 어려운 비밀번호
#                        취약 = 평문 저장이거나 유추하기 쉬운 비밀번호
# 대상: Tomcat, IIS, JEUS. 자동화 범위: Tomcat tomcat-users.xml 평문 비밀번호 길이/복잡도 휴리스틱.
# <user> 요소가 여러 줄에 걸쳐 있어도 요소 단위로 잘라 본다(예전에는 줄 단위라 놓침 - 진단 검수 WEB-R11).
# 비밀번호 원문은 증적에 남기지 않고 길이만 남긴다(S5).
# 1.4.0(커버리지 검수 WEB-C6): 가이드 양호 기준 "비밀번호가 암호화되어 있거나" 를 판정한다 - server.xml 에
# CredentialHandler(MessageDigest/SecretKey, algorithm 지정)가 있고 manager-gui 계정의 password 가 모두 해시 형식
# ([salt$반복$]16진수 32자 이상)이면 GOOD. 예전에는 이 경우도 MANUAL 이라 GOOD 방향을 판정하지 못했다.

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            if ! confdir=$(tomcat_conf_dir); then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="Tomcat 이 감지됐으나 설치 경로(CATALINA_BASE)·conf 폴더를 찾지 못해 관리자 비밀번호를 확인하지 못함"; CHECK_EVIDENCE=""
                return
            fi
            f="$confdir/tomcat-users.xml"
            if [ ! -f "$f" ]; then
                CHECK_STATUS="NA"; CHECK_DETAIL="tomcat-users.xml 이 없음"; CHECK_EVIDENCE="$f 없음"
                return
            fi
            if [ ! -r "$f" ]; then
                CHECK_STATUS="ERROR"; CHECK_DETAIL="$f 를 읽을 수 없음(권한 부족) - 비밀번호 확인 불가"; CHECK_EVIDENCE=""
                return
            fi
            mgr_lines=$(strip_xml_comments "$f" | tr '\n' ' ' | \
                grep -oE '<user([[:space:]]+[A-Za-z_:.-]+[[:space:]]*=[[:space:]]*"[^"]*")*[[:space:]]*/?>' | \
                grep -E 'roles="[^"]*manager-gui')
            if [ -z "$mgr_lines" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="manager-gui 계정이 없어 해당 없음(관리자 페이지 미사용)"; CHECK_EVIDENCE="$f 확인"
                return
            fi
            hashed_realm=""
            sx="$confdir/server.xml"
            [ -r "$sx" ] && strip_xml_comments "$sx" | tr '\n' ' ' | \
                grep -qE '<CredentialHandler[[:space:]][^>]*algorithm[[:space:]]*=[[:space:]]*"[^"]+"' && hashed_realm=1
            weak=""
            plain=""
            evidence=""
            old_ifs=$IFS; IFS='
'
            for line in $mgr_lines; do
                IFS=$old_ifs
                user=$(printf '%s' "$line" | sed -nE 's/.*[[:space:]]username="([^"]*)".*/\1/p')
                pass=$(printf '%s' "$line" | sed -nE 's/.*[[:space:]]password="([^"]*)".*/\1/p')
                len=${#pass}
                evidence="$evidence
계정 $user: 비밀번호 길이=$len"
                if [ "$len" -lt 8 ] || [ "$pass" = "$user" ] || printf '%s' "$pass" | grep -qiE '^(admin|admin123|123admin|password|tomcat)$'; then
                    weak="$weak $user"
                elif [ -z "$hashed_realm" ] || ! printf '%s' "$pass" | grep -qE '^([0-9a-fA-F]+\$[0-9]+\$)?[0-9a-fA-F]{32,}$'; then
                    plain="$plain $user"
                fi
                IFS='
'
            done
            IFS=$old_ifs
            if [ -n "$hashed_realm" ]; then
                CHECK_EVIDENCE="server.xml 에 CredentialHandler(해시 저장) 설정 있음$evidence"
            else
                CHECK_EVIDENCE="tomcat-users.xml 은 기본적으로 평문 저장 방식임(WEB-03 참고)$evidence"
            fi
            if [ -n "$weak" ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="취약한 비밀번호로 판단되는 관리자 계정 존재:$weak"
            elif [ -z "$plain" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="관리자(manager-gui) 계정 비밀번호가 모두 해시(CredentialHandler)로 저장되어 있음"
            else
                CHECK_STATUS="MANUAL"; CHECK_DETAIL="비밀번호 길이는 기준을 충족하나 실제 복잡성(문자 조합)은 자동 판정이 제한적임 — 수동 확인 권장"
            fi
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/IIS/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}
