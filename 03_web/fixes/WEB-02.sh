# WEB-02 (상) 취약한 비밀번호 사용 제한 — 조치 [fix: confirm]
# 대상: Tomcat 전용(checks/WEB-02.sh 참고). 취약 판정된 manager-gui 계정의 비밀번호를 무작위
# 강력 비밀번호로 교체한다. 생성된 비밀번호 원문은 증적/로그에 남기지 않는다(루트 CLAUDE.md
# "민감정보 미기재" 원칙 — WEB-01/02 참고). 새 비밀번호는 백업된 원본 파일에서만 복구 가능하다.
run_fix() {
    detect_web_engines
    case " $WEB_ENGINES " in *" tomcat "*) : ;; *)
        FIX_STATUS="NA"; FIX_DETAIL="Tomcat 이 감지되지 않음"; FIX_EVIDENCE=""
        return
        ;;
    esac

    home=$(tomcat_home)
    f="$home/conf/tomcat-users.xml"
    if [ ! -f "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$f 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi

    mgr_lines=$(strip_xml_comments "$f" | grep -E 'roles="[^"]*manager-gui')
    if [ -z "$mgr_lines" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="manager-gui 계정이 없음"; FIX_EVIDENCE=""
        return
    fi

    fix_backup "$f"
    changed=""
    old_ifs=$IFS; IFS='
'
    for line in $mgr_lines; do
        IFS=$old_ifs
        user=$(printf '%s' "$line" | sed -nE 's/.*username="([^"]*)".*/\1/p')
        pass=$(printf '%s' "$line" | sed -nE 's/.*password="([^"]*)".*/\1/p')
        [ -z "$user" ] && { IFS='
'; continue; }
        len=${#pass}
        weak=0
        if [ "$len" -lt 8 ] || [ "$pass" = "$user" ] || printf '%s' "$pass" | grep -qiE '^(admin|admin123|123admin|password|tomcat)$'; then
            weak=1
        fi
        if [ "$weak" -eq 1 ]; then
            newpass=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-20)
            [ -z "$newpass" ] && newpass="Ch$(date +%s)Xz9!"
            newpass="${newpass}Aa1!"
            sed -i "s#username=\"$user\" password=\"$pass\"#username=\"$user\" password=\"$newpass\"#" "$f"
            changed="$changed $user"
        fi
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$changed" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="취약 비밀번호였던 계정의 비밀번호를 무작위 강력 비밀번호로 교체함:$changed (원문은 증적에 남기지 않음 - 필요 시 백업 파일에서 확인)"
        FIX_EVIDENCE="교체된 계정:$changed"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="취약 비밀번호로 판정된 계정이 없음"
        FIX_EVIDENCE=""
    fi
}
