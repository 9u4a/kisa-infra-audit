# WEB-04 (상) 웹 서비스 디렉터리 리스팅 방지 설정 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            apache_options_enabled "$f" Indexes || continue
            fix_backup "$f"
            # +/- 혼용 문법 오류를 만들지 않도록 토큰 단위로 재구성(lib/common.sh apache_options_disable)
            apache_options_disable "$f" Indexes && applied="$applied apache($f)"
        done
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*autoindex[[:space:]]+on' "$f" 2>/dev/null || continue
            fix_backup "$f"
            web_sed_inplace "$f" -E 's/^([[:space:]]*)autoindex[[:space:]]+on/\1autoindex off/'
            applied="$applied nginx($f)"
        done
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        # 진단과 같은 경로 규칙(tomcat_home/conf, 없으면 /etc/tomcat* - 1.3.3, F-R5)
        tcdir=$(tomcat_conf_dir) || tcdir="(Tomcat conf 폴더를 찾지 못함)"
        f="$tcdir/web.xml"
        if [ -f "$f" ]; then
            listings=$(strip_xml_comments "$f" | awk '/param-name>listings/{f=1} f && /param-value/{print; f=0}' | grep -i 'true')
            if [ -n "$listings" ]; then
                fix_backup "$f"
                awk '
                    /param-name>listings/ { inblock=1 }
                    inblock && /param-value>true</ { sub(/true/, "false"); inblock=0 }
                    { print }
                ' "$f" > "$f.kisa_tmp" && fix_write_back "$f.kisa_tmp" "$f"
                applied="$applied tomcat($f)"
            fi
        fi
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="디렉터리 리스팅을 비활성화함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="디렉터리 리스팅이 활성화된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
