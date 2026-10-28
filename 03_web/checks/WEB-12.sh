# WEB-12 (중) 웹 서비스 링크 사용 금지
# 판단 기준(가이드 원문): 양호 = 심볼릭 링크/aliases/바로가기 사용 미허용 / 취약 = 허용
# Apache: Options 의 FollowSymLinks·+FollowSymLinks·All. Options 지시자가 아예 없으면 Apache 2.4 기본값
# (Options FollowSymLinks)이 적용되므로 VULN(진단 검수 WEB-R10).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            # shellcheck disable=SC2086
            hit=$(web_apache_option_hits FollowSymLinks $WEB_FILES)
            any_opt=""
            for f in $WEB_FILES; do
                awk '{ t = $0; sub(/^[ \t]+/, "", t); split(t, a, /[ \t]+/); if (tolower(a[1]) == "options") { f = 1; exit } } END { exit !f }' "$f" 2>/dev/null && { any_opt=1; break; }
            done
            evidence="$evidence
[Apache] FollowSymLinks/All 검색: ${hit:-없음}"
            [ -z "$any_opt" ] && evidence="$evidence (Options 지시자 없음 - 기본값 FollowSymLinks 적용)"
            if [ -n "$hit" ]; then
                violations="$violations apache"
            elif [ -z "$any_opt" ]; then
                violations="$violations apache(Options 미지정 - 기본값 FollowSymLinks)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*disable_symlinks[[:space:]]+on' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] disable_symlinks on 검색: ${hit:-없음(기본값: 제한 없음 = 심볼릭 링크 허용됨)}"
            [ -z "$hit" ] && violations="$violations nginx(disable_symlinks 미설정)"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true' | web_mask_xml_secrets)
            ctx="$(dirname "$TC_FILE")/context.xml"
            if [ -r "$ctx" ]; then
                hit2=$(strip_xml_comments "$ctx" | grep -inE 'allowLinking[[:space:]]*=[[:space:]]*"?true' | web_mask_xml_secrets)
                [ -n "$hit2" ] && hit="$hit
$ctx: $hit2"
            fi
            evidence="$evidence
[Tomcat] allowLinking=true 검색(server.xml/context.xml): ${hit:-없음(기본값 false)}"
            [ -n "$hit" ] && violations="$violations tomcat"
        fi
    esac

    web_finish "심볼릭 링크/링크 사용이 허용된 엔진" "심볼릭 링크 사용이 제한되어 있음"
}
