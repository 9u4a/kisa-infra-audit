# WEB-04 (상) 웹 서비스 디렉터리 리스팅 방지 설정 — 조치 [fix: auto]
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*Options[^#]*\bIndexes\b' "$f" 2>/dev/null || continue
            grep -qE '^[^#]*Options[^#]*\-Indexes\b' "$f" 2>/dev/null && continue
            fix_backup "$f"
            sed -i -E '/^[^#]*Options[^#]*Indexes/{ s/\bIndexes\b/-Indexes/ }' "$f"
            applied="$applied apache($f)"
        done
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*autoindex[[:space:]]+on' "$f" 2>/dev/null || continue
            fix_backup "$f"
            sed -i -E 's/^([[:space:]]*)autoindex[[:space:]]+on/\1autoindex off/' "$f"
            applied="$applied nginx($f)"
        done
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        f="$home/conf/web.xml"
        if [ -f "$f" ]; then
            listings=$(strip_xml_comments "$f" | awk '/param-name>listings/{f=1} f && /param-value/{print; f=0}' | grep -i 'true')
            if [ -n "$listings" ]; then
                fix_backup "$f"
                awk '
                    /param-name>listings/ { inblock=1 }
                    inblock && /param-value>true</ { sub(/true/, "false"); inblock=0 }
                    { print }
                ' "$f" > "$f.kisa_tmp" && mv "$f.kisa_tmp" "$f"
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
