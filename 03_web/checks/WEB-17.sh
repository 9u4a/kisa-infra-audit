# WEB-17 (중) 웹 서비스 가상 디렉로리 삭제
# 판단 기준(가이드 원문): 양호 = 불필요한 가상 디렉터리가 없음 / 취약 = 존재함
# 대상: Apache, Tomcat, Nginx, WebtoB. "불필요 여부"는 업무 판단이 필요해 목록을 근거로 MANUAL.

run_check() {
    detect_web_engines
    found=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*Alias[[:space:]]+/' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Apache] Alias 목록: ${hit:-없음}"
        [ -n "$hit" ] && found="$found apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*alias[[:space:]]+' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Nginx] alias 목록: ${hit:-없음}"
        [ -n "$hit" ] && found="$found nginx"
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        hit=""
        [ -f "$f" ] && hit=$(grep -nE '<Context[^>]*path="/[^"]' "$f" 2>/dev/null)
        evidence="$evidence
[Tomcat] Context path 목록: ${hit:-없음}"
        [ -n "$hit" ] && found="$found tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -z "$found" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="가상 디렉터리(Alias/Context)가 발견되지 않음"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="가상 디렉터리가 존재함 — 불필요 여부 수동 확인 필요:$found"
    fi
    CHECK_EVIDENCE="$evidence"
}
