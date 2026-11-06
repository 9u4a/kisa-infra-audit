# WEB-12 (중) 웹 서비스 링크 사용 금지 — 조치 [fix: confirm]
# 변경: Apache: Options -FollowSymLinks(기본값을 물려받는 범위는 수동), Nginx: http 블록에 disable_symlinks on; 추가, Tomcat: allowLinking true → "false"(server.xml·context.xml·앱별 컨텍스트)
# 심볼릭 링크로 실제 서비스 콘텐츠가 구성된 경우 이 조치로 서비스가 깨질 수 있다는 점이
# 가이드 '조치 시 영향'에 명시되어 있어 confirm 등급이다(checks/WEB-12.sh 참고).
run_fix() {
    detect_web_engines
    applied=""
    manual_only=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            apache_options_enabled "$f" FollowSymLinks || continue
            fix_backup "$f"
            # +/- 혼용 문법 오류를 만들지 않도록 토큰 단위로 재구성(lib/common.sh apache_options_disable)
            apache_options_disable "$f" FollowSymLinks && applied="$applied apache($f)"
        done
        # checks/WEB-12.sh 와 같은 기준(lib/common_web.sh apache_option_effective): Options 가 없거나 +/- 상대 지정만 있는 범위는
        # 기본값 FollowSymLinks 를 물려받아 VULN 이다(1.5.0 A19). 어느 <Directory> 에 무엇을 넣을지는 서비스 구성에 달려 있어
        # 자동으로 넣지 않고, 위 조치 뒤에도 켜진 범위를 수동 조치로 안내한다.
        left=$(apache_option_effective FollowSymLinks | awk -F '\t' '$1 == "ON" { s = $2; sub(/ =>.*/, "", s); print s }' | head -n 3 | tr '\n' ';' | sed 's/;$//')
        [ -n "$left" ] && manual_only="$manual_only apache(기본값 FollowSymLinks 를 물려받는 범위: $left - 해당 <Directory> 에 'Options -FollowSymLinks' 등 수동 추가)"
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        # checks/WEB-12.sh 와 같은 기준(server 블록별 적용값, 1.5.0 A20): http 블록에 disable_symlinks on 이 없으면 http 블록에
        # 넣는다 - server 블록 하나에만 있던 경우 나머지 server 블록이 이 값을 물려받는다.
        hit=""
        nginx_scoped_stmts | awk -F '\t' '$1 == "DIR" && $2 == "http" && $5 ~ /^disable_symlinks on( |$)/ { f = 1 } END { exit !f }' && hit=1
        if [ -z "$hit" ] && [ -f "$conf" ]; then
            fix_backup "$conf"
            # disable_symlinks 는 http/server/location 컨텍스트 전용 - 파일 끝(main)에 붙이면 nginx 기동 실패
            if nginx_http_insert "$conf" "disable_symlinks on;"; then
                applied="$applied nginx($conf)"
            else
                manual_only="$manual_only nginx($conf 에서 http 블록을 찾지 못해 자동 조치 불가 - http/server 블록에 'disable_symlinks on;' 수동 추가)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
        tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
        # server.xml + conf/context.xml + conf/<엔진>/<호스트>/*.xml, 작은따옴표 값 포함(진단과 같은 대상 - WEB-C4, 1.5.0 A21)
        for f in "$tcdir/server.xml" $(tomcat_context_xmls "$tcdir"); do
            [ -f "$f" ] || continue
            hit=$(strip_xml_comments "$f" | grep -inE "$TOMCAT_ALLOWLINKING_TRUE_RE")
            if [ -n "$hit" ]; then
                fix_backup "$f"
                fix_sed_inplace "$f" -E "s/allowLinking[[:space:]]*=[[:space:]]*(\"true\"|'true'|true)/allowLinking=\"false\"/I"
                applied="$applied tomcat($f)"
            fi
        done
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="심볼릭 링크 사용을 제한함:$applied${manual_only:+ / 수동 조치 필요: $manual_only}"
        FIX_EVIDENCE="$applied"
    elif [ -n "$manual_only" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 불가 - 수동 조치 필요: $manual_only"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="NA"
        FIX_DETAIL="심볼릭 링크가 허용된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
