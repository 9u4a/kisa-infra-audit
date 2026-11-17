# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용 [MySQL] — 조치 [fix: param]
# 값: accounts=잠글 계정(user@host, 쉼표 구분) - 진단 증적의 계정 목록 중 퇴직자·테스트·데모 등 운영자가 불필요하다고 판단한 것
# 변경: 지정 계정 ALTER USER ... ACCOUNT LOCK (삭제하지 않음 - 원복 시 ACCOUNT UNLOCK)
# 영향: 지정 계정으로 하던 DB 접속(애플리케이션·배치)이 즉시 거부됨
# 가이드 조치 방법: 불필요 계정 삭제 또는 잠금. "불필요" 판단은 사람이 한다(진단 MANUAL) - 1.7.0 값 지정 조치로 정책 값의 계정만 잠근다.
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): user@host 형식(따옴표·공백 등 특수문자 없음)·mysql.user 에 있음·지금 잠기지 않음·
# 도구가 접속에 쓰는 계정·root@localhost·MySQL 내부 계정(mysql.sys/mysql.session/mysql.infoschema)이 아님·중복 없음.
run_fix() {
    vals=$(fix_param accounts)
    if [ -z "$vals" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 D-02.accounts 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    command -v mysql >/dev/null 2>&1 || { FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""; return; }
    errs=""; seen=" "
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        case "$seen" in *" $a "*) errs="$errs / $a: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$a "
        u=${a%@*}; h=${a##*@}
        if [ "$u" = "$a" ] || ! printf '%s' "$u" | grep -qE '^[A-Za-z0-9_.$-]+$' || ! printf '%s' "$h" | grep -qE '^[A-Za-z0-9_.%:/-]+$'; then
            errs="$errs / $a: user@host 형식이 아님(영문·숫자·_.\$-, 호스트는 %·IP·이름)"; continue
        fi
        case "$u" in mysql.sys|mysql.session|mysql.infoschema) errs="$errs / $a: MySQL 내부 계정"; continue ;; esac
        [ "$u" = "root" ] && [ "$h" = "localhost" ] && { errs="$errs / $a: 기본 관리자(root@localhost)는 잠그지 않음"; continue; }
        [ "$u" = "${DB_USER:-root}" ] && { errs="$errs / $a: 도구가 접속에 쓰는 계정"; continue; }
        st=$(mysql_query "SELECT account_locked FROM mysql.user WHERE user='$u' AND host='$h';") || { errs="$errs / $a: 계정 조회 실패"; continue; }
        case "$st" in
            N) ;;
            Y) errs="$errs / $a: 이미 잠김" ;;
            *) errs="$errs / $a: mysql.user 에 없는 계정" ;;
        esac
    done <<EOF
$vals
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    done_list=""; failed=""
    for a in $seen; do
        u=${a%@*}; h=${a##*@}
        fix_db_queue_rollback mysql "ALTER USER '$u'@'$h' ACCOUNT UNLOCK;"
        if mysql_query "ALTER USER '$u'@'$h' ACCOUNT LOCK;" >/dev/null && [ "$(mysql_query "SELECT account_locked FROM mysql.user WHERE user='$u' AND host='$h';")" = Y ]; then
            done_list="$done_list $a"
        else
            failed="$failed $a"
        fi
    done
    FIX_EVIDENCE=$(mysql_query "SELECT user, host, account_locked FROM mysql.user ORDER BY user, host;" 2>/dev/null)
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="계정 잠금 실패:$failed"
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="지정 계정을 잠금(ACCOUNT LOCK):$done_list"
    fi
}
