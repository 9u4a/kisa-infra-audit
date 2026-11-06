# WEB-12 (중) 웹 서비스 링크 사용 금지
# 판단 기준(가이드 원문): 양호 = 심볼릭 링크/aliases/바로가기 사용 미허용 / 취약 = 허용
# Apache: 범위(<Directory> 등)마다 실제 적용되는 Options 에 FollowSymLinks 가 남으면 VULN. Options 가 없거나 +/- 상대 지정만
# 있으면 Apache 2.4 기본값(Options FollowSymLinks)이 상속된다(진단 검수 WEB-R10, 1.5.0 A19 - 예전에는 "Options -Indexes" 처럼
# 상대 지정만 있어도 Options 가 있다고 보고 기본값을 놓쳤다). Nginx: server 블록마다 적용되는 disable_symlinks(server 값 >
# http 값 > 기본 off)와 location 등의 재지정 값이 모두 on 이어야 GOOD(A20 - 예전에는 server 하나에만 있어도 GOOD).
# Tomcat: server.xml·context.xml·앱별 컨텍스트(conf/<엔진>/<호스트>/*.xml)의 allowLinking=true(작은따옴표 포함, A21).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            eff=$(apache_option_effective FollowSymLinks)
            on=$(printf '%s\n' "$eff" | awk -F '\t' '$1 == "ON" { s = $2; sub(/ =>.*/, "", s); print s }')
            evidence="$evidence
[Apache] 범위별 적용 Options(FollowSymLinks 켜짐 = ON):
$(printf '%s\n' "$eff" | tr '\t' ' ')"
            if [ -z "$eff" ]; then
                errors="$errors apache(Options 적용값 계산 실패)"
            elif [ -n "$on" ]; then
                violations="$violations apache($(printf '%s\n' "$on" | head -n 3 | tr '\n' ';' | sed 's/;$//'))"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            eff=$(nginx_server_effective disable_symlinks off)
            bad=$(printf '%s\n' "$eff" | awk -F '\t' '
                $1 == "SRV" && $3 !~ /^on( |$)/ { print $2 " = " $3 " (" $4 ")" }
                $1 == "INNER" && $3 !~ /^on( |$)/ { print $2 " = " $3 " (location 등 재지정)" }')
            evidence="$evidence
[Nginx] server 블록별 적용 disable_symlinks(기본값 off = 심볼릭 링크 허용):
$(printf '%s\n' "$eff" | tr '\t' ' ')"
            if [ -z "$eff" ]; then
                errors="$errors nginx(설정 구조 해석 실패)"
            elif [ -n "$bad" ]; then
                violations="$violations nginx($(printf '%s\n' "$bad" | head -n 3 | tr '\n' ';' | sed 's/;$//'))"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            hit=""
            for f in "$TC_FILE" $(tomcat_context_xmls "$(dirname "$TC_FILE")"); do
                if [ ! -r "$f" ]; then errors="$errors tomcat($f 읽기 불가)"; continue; fi
                h=$(strip_xml_comments "$f" | grep -inE "$TOMCAT_ALLOWLINKING_TRUE_RE" | web_mask_xml_secrets)
                [ -n "$h" ] && hit="$hit
$f: $h"
            done
            evidence="$evidence
[Tomcat] allowLinking=true 검색(server.xml/context.xml/conf/<엔진>/<호스트>/*.xml): ${hit:-없음(기본값 false)}"
            [ -n "$hit" ] && violations="$violations tomcat"
        fi
    esac

    web_finish "심볼릭 링크/링크 사용이 허용된 엔진" "심볼릭 링크 사용이 제한되어 있음"
}
