# WEB-18 (상) 웹 서비스 WebDAV 비활성화
# 판단 기준(가이드 원문): 양호 = WebDAV 비활성화 / 취약 = 활성화
# 대상: Apache, Nginx, IIS, WebtoB
# Apache 는 실제 로드되는 설정(Debian mods-enabled/dav*.load 포함)에서 dav_module 로드·Dav On 을 찾는다(WEB-R1).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*(LoadModule[[:space:]]+dav_module|Dav[[:space:]]+On)' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] WebDAV(dav_module/Dav On) 검색: ${hit:-없음}"
            [ -n "$hit" ] && violations="$violations apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*dav_methods' "$f" 2>/dev/null | grep -vE 'dav_methods[[:space:]]+off')
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] dav_methods 검색: ${hit:-없음(코어 모듈에 WebDAV 미포함 시 항상 비활성)}"
            [ -n "$hit" ] && violations="$violations nginx"
        fi
    esac

    web_finish "WebDAV 가 활성화된 엔진" "WebDAV 가 비활성화되어 있음"
}
