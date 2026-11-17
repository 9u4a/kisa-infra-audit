# WEB-17 (중) 웹 서비스 가상 디렉로리 삭제
# 판단 기준(가이드 원문): 양호 = 불필요한 가상 디렉터리가 없음 / 취약 = 존재함
# 대상: Apache, Tomcat, Nginx, WebtoB. "불필요 여부"는 업무 판단이 필요해 목록을 근거로 MANUAL.

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*(Script)?Alias(Match)?[[:space:]]+/' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] Alias 목록: ${hit:-없음}"
            [ -n "$hit" ] && manuals="$manuals apache"
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*alias[[:space:]]+' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] alias 목록: ${hit:-없음}"
            [ -n "$hit" ] && manuals="$manuals nginx"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -nE '<Context[^>]*path="/[^"]' | web_mask_xml_secrets)
            evidence="$evidence
[Tomcat] Context path 목록: ${hit:-없음}"
            [ -n "$hit" ] && manuals="$manuals tomcat"
        fi
    esac

    # 1.7.0 값 지정 조치: WEB-17.aliases 후보(Apache Alias 류 첫 인자, Nginx alias 가 든 location 의 URL) - lib/policy_draft.py 가 읽는다
    cand=""
    case " $WEB_ENGINES " in *" apache "*)
        for f in $(apache_conf_path) $(apache_extra_confs); do
            [ -f "$f" ] && cand="$cand
$(awk '{ t = $0; sub(/^[ \t]+/, "", t); if (t ~ /^#/) next; n = split(t, a, /[ \t]+/); d = tolower(a[1]); g = a[2]; gsub(/"/, "", g)
        if (d ~ /^(script)?alias(match)?$/ && g ~ /^\//) print g }' "$f" 2>/dev/null)"
        done
    esac
    case " $WEB_ENGINES " in *" nginx "*)
        for f in $(nginx_conf_path) $(nginx_extra_confs); do
            [ -f "$f" ] && cand="$cand
$(awk '{ t = $0; sub(/#.*/, "", t) }
        match(t, /^[ \t]*location[ \t]+[^{]*\{/) { h = substr(t, RSTART, RLENGTH); sub(/\{$/, "", h); sub(/[ \t]+$/, "", h); n = split(h, a, /[ \t]+/); loc = a[n] }
        t ~ /(^|[ \t;{])alias[ \t]/ && loc != "" { print loc }' "$f" 2>/dev/null)"
        done
    esac
    cand=$(printf '%s\n' "$cand" | grep -v '^$' | grep -v ',' | sort -u | tr '\n' ',' | sed 's/,$//')
    [ -n "$cand" ] && evidence="$evidence

[candidates] $cand"

    web_finish "불필요한 가상 디렉터리가 있는 엔진" "가상 디렉터리(Alias/Context)가 발견되지 않음" "가상 디렉터리가 존재함 — 불필요 여부 수동 확인 필요"
}
