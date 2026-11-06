# WEB-22 (하) 에러 페이지 관리
# 판단 기준(가이드 원문): 양호 = 에러 페이지가 별도로 지정됨 / 취약 = 미지정 또는 정보 노출
# 1.5.0 A20: 요청을 받는 모든 범위에 404 에러 페이지가 지정돼야 GOOD - 예전에는 파일 어딘가에 한 줄이라도 있으면 GOOD 이었다.
#   Apache: <VirtualHost> 마다 자기 ErrorDocument 404 또는 서버 전역 ErrorDocument 404(VirtualHost 가 물려받음), VirtualHost 가
#           받지 않는 Listen 포트가 있으면 서버 전역(main)에도 필요.
#   Nginx : server 블록마다 적용되는 error_page(블록에 하나라도 있으면 바깥 값을 물려받지 않음)에 404 가 있어야 하고,
#           location 등 안쪽 블록도 error_page 를 두면 404 를 지정해야 한다(실무 적용 검증 P-05, nginx_error_page_gaps).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            hit=""
            for f in $WEB_FILES; do
                l=$(grep -niE '^[^#]*ErrorDocument' "$f" 2>/dev/null)
                [ -n "$l" ] && hit="$hit
$f: $l"
            done
            # 1.5.0 C2: RHEL 기본 welcome.conf 는 루트 URL(<LocationMatch "^/+$">) 전용 ErrorDocument 403 하나뿐인데
            # 예전에는 ErrorDocument 가 한 줄이라도 있으면 GOOD 이었다 - nginx(P-05)와 같이 404 지정을 요구한다
            res=$(apache_vhost_scopes '^errordocument[ \t]+404([ \t]|$)' | awk -F '\t' '
                $1 == "MAIN" { na = $3; gi = $5; next }
                $1 == "VH" {
                    if ($4) print "OK\t" $2 " (자체 404)"
                    else if (gi) print "OK\t" $2 " (서버 전역 404 상속)"
                    else print "BAD\t" $2
                }
                END { if (na) print (gi ? "OK" : "BAD") "\t서버 전역(VirtualHost 가 받지 않는 Listen 포트)" }')
            bad=$(printf '%s\n' "$res" | awk -F '\t' '$1 == "BAD" { print $2 }')
            evidence="$evidence
[Apache] ErrorDocument 검색: ${hit:-없음}
[Apache] 범위별 ErrorDocument 404:
$(printf '%s\n' "$res" | tr '\t' ' ')"
            if [ -z "$res" ]; then
                errors="$errors apache(VirtualHost 범위 해석 실패)"
            elif [ -n "$bad" ]; then
                violations="$violations apache(ErrorDocument 404 없음: $(printf '%s\n' "$bad" | head -n 3 | tr '\n' ';' | sed 's/;$//'))"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            gaps=""
            for f in $WEB_FILES; do
                for n in $(nginx_error_page_gaps "$f"); do gaps="$gaps $f:$n"; done
            done
            eff=$(nginx_server_effective error_page "" multi)
            bad=$(printf '%s\n' "$eff" | awk -F '\t' '$1 == "SRV" && (" " $3 " ") !~ /[ ]404[ ]/ { print $2 " (" ($3 == "" ? "error_page 없음" : "404 미지정") ")" }')
            evidence="$evidence
[Nginx] server 블록별 적용 error_page:
$(printf '%s\n' "$eff" | grep -v '^INNER' | tr '\t' ' ')${gaps:+
[Nginx] 404 를 지정하지 않은 error_page 블록(바깥 블록 설정을 물려받지 않음):$gaps}"
            if [ -z "$eff" ]; then
                errors="$errors nginx(설정 구조 해석 실패)"
            elif [ -n "$bad" ] || [ -n "$gaps" ]; then
                violations="$violations nginx($(printf '%s\n' "$bad" | head -n 3 | tr '\n' ';' | sed 's/;$//')${gaps:+ 404 미지정 블록:$gaps})"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf web.xml; then
            hit=$(strip_xml_comments "$TC_FILE" | grep -c '<error-page>')
            evidence="$evidence
[Tomcat] $TC_FILE error-page 요소 개수: ${hit:-0}"
            { [ -z "$hit" ] || [ "$hit" -eq 0 ]; } && violations="$violations tomcat"
        fi
    esac

    web_finish "에러 페이지가 별도로 지정되지 않은 엔진" "에러 페이지가 별도로 지정되어 있음"
}
