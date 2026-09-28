# WEB-06 (상) 웹 서비스 상위 디렉터리 접근 제한 설정
# 판단 기준(가이드 원문): 양호 = 상위 디렉터리 접근 기능 제거 / 취약 = 제거하지 않음
# 자동화 범위: Tomcat Context allowLinking(명시적 true 시 취약). Apache/Nginx 는 단일 지시자로
# 매핑되지 않아(가이드 예시가 인증 설정을 곁들임) MANUAL 로 안내한다.

run_check() {
    detect_web_engines
    violations=""
    manuals=""
    evidence=""
    checked=0

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
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        hit=""
        [ -f "$f" ] && hit=$(strip_xml_comments "$f" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true')
        evidence="$evidence
[Tomcat] allowLinking=true 검색: ${hit:-없음(기본값 false)}"
        [ -n "$hit" ] && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="상위 디렉터리 접근 제한이 해제된 엔진:$violations"
    elif [ -n "$manuals" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="자동 판정이 제한적인 엔진 존재:$manuals"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="상위 디렉터리 접근이 제한되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}
