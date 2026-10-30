# WEB-08 (하) 웹 서비스 파일 업로드 및 다운로드 용량 제한 — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 가이드 권고에 맞춰 넉넉한 상한값(10MB)을 기본값으로 설정한다 - 실제 업무에 필요한 값은
# 조직마다 다를 수 있지만, "제한이 전혀 없는" 상태보다 안전한 값이라 U-28류 문제는 아니다.
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        hit=""
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*LimitRequestBody' "$f" 2>/dev/null && hit=1
        done
        # checks/WEB-08.sh 와 같은 기준: LimitRequestBody 0 은 무제한(VULN) - 10MB 로 바꾼다(1.3.3)
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qiE '^[^#]*LimitRequestBody[[:space:]]+0+([^0-9]|$)' "$f" 2>/dev/null || continue
            fix_backup "$f"
            fix_sed_inplace "$f" -E 's/^([^#]*[Ll][Ii][Mm][Ii][Tt][Rr][Ee][Qq][Uu][Ee][Ss][Tt][Bb][Oo][Dd][Yy][[:space:]]+)0+([^0-9]|$)/\110485760\2/'
            applied="$applied apache($f: 0->10485760)"
        done
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            printf '\n# KISA WEB-08: 업로드 용량 제한(10MB)\nLimitRequestBody 10485760\n' >> "$conf"
            applied="$applied apache($conf)"
        fi
    esac

    # Nginx: client_max_body_size 미설정은 기본값 1m 이 적용돼 진단도 GOOD 이다. 0(무제한)만 10m 으로 바꾼다
    # (예전에는 Nginx 분기가 없어 진단 VULN 인데 조치가 NA 로 끝났다 - 커버리지 검수 WEB-C5).
    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*client_max_body_size[[:space:]]+0+[[:space:]]*;' "$f" 2>/dev/null || continue
            fix_backup "$f"
            fix_sed_inplace "$f" -E 's/^([^#]*client_max_body_size[[:space:]]+)0+([[:space:]]*;)/\110m\2/'
            applied="$applied nginx($f: 0->10m)"
        done
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
        tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
        f="$tcdir/server.xml"
        if [ -f "$f" ]; then
            # checks/WEB-08.sh 와 같은 기준: XML 주석을 지운 뒤 찾고, 음수(-1 = 무제한)는 10MB 로 바꾼다(1.3.3)
            hit=$(strip_xml_comments "$f" | grep -oE '(maxPostSize|maxSwallowSize)[[:space:]]*=[[:space:]]*"[^"]*"')
            if printf '%s\n' "$hit" | grep -qE '"[[:space:]]*-[0-9]'; then
                fix_backup "$f"
                fix_sed_inplace "$f" -E 's/((maxPostSize|maxSwallowSize)[[:space:]]*=[[:space:]]*")[[:space:]]*-[0-9]+"/\110485760"/g'
                applied="$applied tomcat($f: 음수->10485760)"
            elif [ -z "$hit" ]; then
                fix_backup "$f"
                # Connector 태그는 속성이 여러 줄에 걸쳐 있는 경우가 흔해(실제 tomcat:10 기본
                # server.xml 로 실기 확인) 닫는 ">" 를 찾는 sed 대신, "<Connector" 문자열이
                # 있는 그 줄에서 바로 뒤에 속성을 삽입한다(같은 줄에 port="8080" 도 함께 있음).
                awk '
                    !done && /<Connector[^>]*port="8080"/ { sub(/<Connector/, "<Connector maxPostSize=\"10485760\""); done=1 }
                    { print }
                ' "$f" > "$f.kisa_tmp" && fix_write_back "$f.kisa_tmp" "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="업로드 용량 제한(10MB)을 설정함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="제한이 필요한 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
