# WEB-14 (상) 웹 서비스 경로 내 파일의 접근 통제
# 판단 기준(가이드 원문): 양호 = 주요 설정 파일/디렉터리에 불필요한 접근 권한이 없음
#                        취약 = 불필요한 접근 권한이 부여됨
# 자동화 범위: 주 설정 파일의 group/other 쓰기 권한 여부로 판정 (750 이하 권고).

run_check() {
    detect_web_engines
    violations=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        if [ -f "$conf" ]; then
            perm=$(stat -L -c '%a' "$conf" 2>/dev/null)
            evidence="$evidence
[Apache] $conf perm=$perm"
            [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null && violations="$violations apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        if [ -f "$conf" ]; then
            perm=$(stat -L -c '%a' "$conf" 2>/dev/null)
            evidence="$evidence
[Nginx] $conf perm=$perm"
            [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null && violations="$violations nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        if [ -f "$f" ]; then
            perm=$(stat -L -c '%a' "$f" 2>/dev/null)
            evidence="$evidence
[Tomcat] $f perm=$perm"
            [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null && violations="$violations tomcat"
        fi
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="주요 설정 파일 권한이 750을 초과하는 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="주요 설정 파일 권한이 750 이하로 설정됨"
    fi
    CHECK_EVIDENCE="$evidence"
}
