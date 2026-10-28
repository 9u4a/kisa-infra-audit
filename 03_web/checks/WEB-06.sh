# WEB-06 (상) 웹 서비스 상위 디렉터리 접근 제한 설정
# 판단 기준(가이드 원문): 양호 = 상위 디렉터리 접근 기능 제거 / 취약 = 제거하지 않음
# 자동화 범위: Tomcat Context allowLinking(명시적 true 시 취약, server.xml·context.xml). Apache/Nginx 는 단일
# 지시자로 매핑되지 않아(가이드 예시가 인증 설정을 곁들임) MANUAL 로 안내한다.

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        manuals="$manuals apache(상위 디렉터리 접근 제한은 AllowOverride/인증 설정 조합으로 판단 필요 - 자동 판정 제한적)"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        manuals="$manuals nginx(경로 접근 제한은 location 별 auth_basic 설정 조합으로 판단 필요 - 자동 판정 제한적)"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true' | web_mask_xml_secrets)
            ctx="$(dirname "$TC_FILE")/context.xml"
            [ -r "$ctx" ] && hit2=$(strip_xml_comments "$ctx" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true' | web_mask_xml_secrets) && [ -n "$hit2" ] && hit="$hit
$ctx: $hit2"
            evidence="$evidence
[Tomcat] allowLinking=true 검색(server.xml/context.xml): ${hit:-없음(기본값 false)}"
            [ -n "$hit" ] && violations="$violations tomcat"
        fi
    esac

    web_finish "상위 디렉터리 접근 제한이 해제된 엔진" "상위 디렉터리 접근이 제한되어 있음"
}
