# WEB-18 (상) 웹 서비스 WebDAV 비활성화
# 판단 기준(가이드 원문): 양호 = WebDAV 비활성화 / 취약 = 활성화
# 대상: Apache, Nginx, IIS, WebtoB

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
            l=$(grep -nE '^[^#]*(LoadModule[[:space:]]+dav_module|Dav[[:space:]]+On)' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Apache] WebDAV(dav_module/Dav On) 검색: ${hit:-없음}"
        [ -n "$hit" ] && violations="$violations apache"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            l=$(grep -nE '^[^#]*dav_methods' "$f" 2>/dev/null)
            [ -n "$l" ] && hit="$hit
$f: $l"
        done
        evidence="$evidence
[Nginx] dav_methods 검색: ${hit:-없음(코어 모듈에 WebDAV 미포함 시 항상 비활성)}"
        [ -n "$hit" ] && violations="$violations nginx"
    esac

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="대상 엔진(Apache/Nginx/IIS/WebtoB)이 감지되지 않음 (감지된 엔진: ${WEB_ENGINES:-없음})"
    elif [ -n "$violations" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="WebDAV 가 활성화된 엔진:$violations"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="WebDAV 가 비활성화되어 있음"
    fi
    CHECK_EVIDENCE="$evidence"
}
