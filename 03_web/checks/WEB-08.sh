# WEB-08 (하) 웹 서비스 파일 업로드 및 다운로드 용량 제한
# 판단 기준(가이드 원문): 양호 = 업로드/다운로드 용량을 제한한 경우 / 취약 = 제한하지 않은 경우

run_check() {
    detect_web_engines
    violations=""
    evidence=""
    checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*LimitRequestBody' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Apache] LimitRequestBody: ${hit:-미설정}"
        [ -z "$hit" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*client_max_body_size' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Nginx] client_max_body_size: ${hit:-미설정(기본값 1MB로 사실상 제한 있음)}"
        # nginx 는 client_max_body_size 미설정 시에도 기본값(1m)이 적용되므로 미설정을 VULN 처리하지 않음
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        home=$(tomcat_home)
        f="$home/conf/server.xml"
        hit=""
        [ -f "$f" ] && hit=$(grep -nE 'maxPostSize|maxSwallowSize' "$f" 2>/dev/null)
        evidence="$evidence
[Tomcat] maxPostSize/maxSwallowSize: ${hit:-미설정}"
        [ -z "$hit" ] && violations="$violations tomcat"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="지원 엔진이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="업로드/다운로드 용량 제한이 설정되지 않은 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="업로드/다운로드 용량 제한이 설정되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}
