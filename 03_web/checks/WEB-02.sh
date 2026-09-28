# WEB-02 (상) 취약한 비밀번호 사용 제한
# 판단 기준(가이드 원문): 양호 = 관리자 비밀번호가 암호화되어 있거나 유추 어려운 비밀번호
#                        취약 = 평문 저장이거나 유추하기 쉬운 비밀번호
# 대상: Tomcat, IIS, JEUS. 자동화 범위: Tomcat tomcat-users.xml 평문 비밀번호 길이/복잡도 휴리스틱.

run_check() {
    detect_web_engines
    case " $WEB_ENGINES " in
        *" tomcat "*)
            home=$(tomcat_home)
            f="$home/conf/tomcat-users.xml"
            if [ ! -f "$f" ]; then
                CHECK_STATUS="NA"; CHECK_DETAIL="tomcat-users.xml 이 없음"; CHECK_EVIDENCE=""
                return
            fi
            mgr_lines=$(strip_xml_comments "$f" | grep -E 'roles="[^"]*manager-gui')
            if [ -z "$mgr_lines" ]; then
                CHECK_STATUS="GOOD"; CHECK_DETAIL="manager-gui 계정이 없어 해당 없음(관리자 페이지 미사용)"; CHECK_EVIDENCE=""
                return
            fi
            weak=""
            evidence=""
            old_ifs=$IFS; IFS='
'
            for line in $mgr_lines; do
                IFS=$old_ifs
                user=$(printf '%s' "$line" | sed -nE 's/.*username="([^"]*)".*/\1/p')
                pass=$(printf '%s' "$line" | sed -nE 's/.*password="([^"]*)".*/\1/p')
                len=${#pass}
                evidence="$evidence
계정 $user: 비밀번호 길이=$len"
                if [ "$len" -lt 8 ] || [ "$pass" = "$user" ] || printf '%s' "$pass" | grep -qiE '^(admin|admin123|123admin|password|tomcat)$'; then
                    weak="$weak $user"
                fi
                IFS='
'
            done
            IFS=$old_ifs
            CHECK_EVIDENCE="tomcat-users.xml 은 기본적으로 평문 저장 방식임(WEB-03 참고)$evidence"
            if [ -n "$weak" ]; then
                CHECK_STATUS="VULN"; CHECK_DETAIL="취약한 비밀번호로 판단되는 관리자 계정 존재:$weak"
            else
                CHECK_STATUS="MANUAL"; CHECK_DETAIL="비밀번호 길이는 기준을 충족하나 실제 복잡성(문자 조합)은 자동 판정이 제한적임 — 수동 확인 권장"
            fi
            ;;
        *)
            CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Tomcat/IIS/JEUS)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"; CHECK_EVIDENCE=""
            ;;
    esac
}
