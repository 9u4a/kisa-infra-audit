# WEB-08 (하) 웹 서비스 파일 업로드 및 다운로드 용량 제한
# 판단 기준(가이드 원문): 양호 = 업로드/다운로드 용량을 제한한 경우 / 취약 = 제한하지 않은 경우
# 무제한 값도 "제한하지 않음"으로 본다(진단 검수 WEB-R10): Apache LimitRequestBody 0, Nginx client_max_body_size 0,
# Tomcat maxPostSize/maxSwallowSize 음수(-1). Tomcat 은 XML 주석을 지운 뒤 찾고, 증적의 비밀번호류 속성은 가린다(S5).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*LimitRequestBody' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Apache] LimitRequestBody: ${hit:-미설정}"
            if [ -z "$hit" ]; then
                violations="$violations apache(미설정)"
            elif printf '%s\n' "$hit" | grep -qiE 'LimitRequestBody[[:space:]]+0+([^0-9]|$)'; then
                violations="$violations apache(LimitRequestBody 0 = 무제한)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -nE '^[^#]*client_max_body_size' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            evidence="$evidence
[Nginx] client_max_body_size: ${hit:-미설정(기본값 1MB로 사실상 제한 있음)}"
            # nginx 는 client_max_body_size 미설정 시에도 기본값(1m)이 적용되므로 미설정을 VULN 처리하지 않음
            printf '%s\n' "$hit" | grep -qE 'client_max_body_size[[:space:]]+0+[[:space:]]*;' && \
                violations="$violations nginx(client_max_body_size 0 = 무제한)"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf server.xml; then
            # 1.5.0 A22: AJP 가 아닌 모든 HTTP Connector 마다 maxPostSize/maxSwallowSize 가 있어야 한다(예전에는 Connector 하나에만
            # 있어도 GOOD). 작은따옴표 값도 읽는다. 음수(-1 = 무제한)는 어느 Connector 든 VULN.
            conns=$(tomcat_http_connectors "$TC_FILE")
            ok=""; miss=""; neg=""
            while IFS= read -r c; do
                [ -n "$c" ] || continue
                port=$(xml_attr "$c" port); mp=$(xml_attr "$c" maxPostSize); ms=$(xml_attr "$c" maxSwallowSize)
                d="port=${port:-?}(maxPostSize=${mp:-미설정},maxSwallowSize=${ms:-미설정})"
                if printf '%s %s' "$mp" "$ms" | grep -qE '(^|[[:space:]])[[:space:]]*-[0-9]'; then neg="$neg $d"
                elif [ -z "$mp" ] && [ -z "$ms" ]; then miss="$miss $d"
                else ok="$ok $d"; fi
            done <<EOF_TC08
$conns
EOF_TC08
            evidence="$evidence
[Tomcat] $TC_FILE HTTP Connector 별 용량 제한 - 설정됨:${ok:- 없음} / 미설정:${miss:- 없음} / 무제한(음수):${neg:- 없음}"
            if [ -z "$conns" ]; then
                manuals="$manuals tomcat(HTTP Connector 없음(AJP 전용 등) - 앞단 웹 서버의 업로드 제한을 확인)"
            elif [ -n "$neg" ]; then
                violations="$violations tomcat(음수 = 무제한:$neg)"
            elif [ -n "$miss" ]; then
                violations="$violations tomcat(미설정:$miss)"
            fi
        fi
    esac

    web_finish "업로드/다운로드 용량 제한이 설정되지 않은(또는 무제한인) 엔진" "업로드/다운로드 용량 제한이 설정되어 있음"
}
