# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한
# 판단 기준(가이드 원문): 양호 = HTTP 응답 헤더에서 웹 서버 정보가 노출되지 않음
#                        취약 = 노출됨
# Apache ServerTokens 는 마지막 값이 적용된다 - 실제 로드 순서상 마지막 값이 Prod(ProductOnly) 일 때만 GOOD
# (Debian 은 conf-enabled/security.conf 의 "ServerTokens OS" 가 나중에 읽힌다 - 진단 검수 WEB-R11).
# Nginx: server 블록마다 적용되는 server_tokens(server 값 > http 값 > 기본 on)와 location 등의 재지정 값이 모두 off 여야
# GOOD(1.5.0 A20 - 예전에는 파일 어딘가에 off 가 있으면 server 블록 하나뿐이어도 GOOD 이었다).
# Tomcat: AJP 가 아닌 모든 <Connector> 에 server 속성이 있어야 GOOD(A22 - 예전에는 Connector 하나에만 있어도 GOOD,
# 속성이 다음 줄에 있으면 거짓 VULN).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            last=$(apache_last_directive ServerTokens)
            val=$(printf '%s' "$last" | cut -f1 | tr 'A-Z' 'a-z')
            shown="없음(기본값 Full - 상세 정보 노출)"
            [ -n "$last" ] && shown=$(printf '%s' "$last" | cut -f2)
            evidence="$evidence
[Apache] 적용되는(마지막) ServerTokens: $shown"
            case "$val" in
                prod|productonly) : ;;
                *) violations="$violations apache" ;;
            esac
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            eff=$(nginx_server_effective server_tokens on)
            bad=$(printf '%s\n' "$eff" | awk -F '\t' '
                $1 == "SRV" && $3 != "off" { print $2 " = " $3 " (" $4 ")" }
                $1 == "INNER" && $3 != "off" { print $2 " = " $3 " (location 등 재지정)" }')
            evidence="$evidence
[Nginx] server 블록별 적용 server_tokens(기본값 on - 버전 정보 노출):
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
            conns=$(tomcat_http_connectors "$TC_FILE")
            ok=""; miss=""
            while IFS= read -r c; do
                [ -n "$c" ] || continue
                port=$(xml_attr "$c" port)
                if printf '%s' "$c" | grep -qE '[[:space:]]server[[:space:]]*='; then
                    ok="$ok port=${port:-?}(server=\"$(xml_attr "$c" server)\")"
                else
                    miss="$miss port=${port:-?}"
                fi
            done <<EOF_TC16
$conns
EOF_TC16
            evidence="$evidence
[Tomcat] HTTP Connector server 속성 - 지정됨:${ok:- 없음} / 미지정(기본 배너 노출):${miss:- 없음}"
            if [ -z "$conns" ]; then
                manuals="$manuals tomcat(HTTP Connector 없음(AJP 전용 등) - 앞단 웹 서버의 헤더 노출을 확인)"
            elif [ -n "$miss" ]; then
                violations="$violations tomcat(server 속성 없는 Connector:$miss)"
            fi
        fi
    esac

    web_finish "응답 헤더에 서버 정보가 노출되는 엔진" "응답 헤더의 서버 정보 노출이 제한되어 있음"
}
