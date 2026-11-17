# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용 [Oracle] — 조치 [fix: param]
# 값: accounts=잠글 계정 이름(쉼표 구분, 대소문자 무관 - 대문자로 맞춤) - 진단 증적의 dba_users 목록 중 불필요하다고 판단한 것
# 변경: 지정 계정 ALTER USER ... ACCOUNT LOCK (삭제하지 않음 - 원복 시 ACCOUNT UNLOCK)
# 영향: 지정 계정으로 하던 DB 접속(애플리케이션·배치)이 즉시 거부됨
# 가이드 조치 방법: 불필요 계정 삭제 또는 잠금. "불필요" 판단은 사람이 한다(진단 MANUAL) - 1.7.0 값 지정 조치로 정책 값의 계정만 잠근다.
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 계정 이름 형식·dba_users 에 있음·OPEN 상태·Oracle 내장 계정(oracle_maintained='Y',
# SYS·SYSTEM 포함)·도구 접속 계정이 아님·중복 없음.
run_fix() {
    vals=$(fix_param accounts)
    if [ -z "$vals" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 D-02.accounts 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    errs=""; seen=" "
    self=$(printf '%s' "${DB_USER:-}" | tr '[:lower:]' '[:upper:]')
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        printf '%s' "$a" | grep -qE '^[A-Za-z][A-Za-z0-9_$#]*$' || { errs="$errs / $a: 계정 이름 형식이 아님"; continue; }
        u=$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')
        case "$seen" in *" $u "*) errs="$errs / $a: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$u "
        case "$u" in SYS|SYSTEM) errs="$errs / $u: 필수 관리 계정은 잠그지 않음"; continue ;; esac
        [ -n "$self" ] && [ "$u" = "$self" ] && { errs="$errs / $u: 도구가 접속에 쓰는 계정"; continue; }
        st=$(oracle_query "SELECT account_status || '|' || oracle_maintained FROM dba_users WHERE username = '$u';" | tr -d ' \r' | head -n 1)
        case "$st" in
            OPEN\|N) ;;
            *\|Y) errs="$errs / $u: Oracle 내장 계정(oracle_maintained=Y)" ;;
            ?*\|N) errs="$errs / $u: OPEN 상태가 아님(${st%|*})" ;;
            *) errs="$errs / $u: dba_users 에 없는 계정" ;;
        esac
    done <<EOF
$vals
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi
    done_list=""; failed=""
    for u in $seen; do
        fix_db_queue_rollback oracle "ALTER USER \"$u\" ACCOUNT UNLOCK;"
        oracle_query "ALTER USER \"$u\" ACCOUNT LOCK;" >/dev/null
        st=$(oracle_query "SELECT account_status FROM dba_users WHERE username = '$u';" | tr -d ' \r' | head -n 1)
        case "$st" in *LOCKED*) done_list="$done_list $u" ;; *) failed="$failed $u($st)" ;; esac
    done
    FIX_EVIDENCE=$(oracle_query "SELECT username, account_status FROM dba_users WHERE oracle_maintained = 'N' ORDER BY username;" 2>/dev/null)
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="계정 잠금 실패:$failed"
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="지정 계정을 잠금(ACCOUNT LOCK):$done_list"
    fi
}
