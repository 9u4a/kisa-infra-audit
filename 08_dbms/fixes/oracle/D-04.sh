# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용 [Oracle] — 조치 [fix: param]
# 값: accounts=DBA 롤을 회수할 계정 이름(쉼표 구분, 대문자로 맞춤) - 진단 증적의 DBA 롤 보유자 중 불필요한 것
# 변경: 지정 계정에서 REVOKE DBA (원복 시 GRANT DBA - 원래 ADMIN OPTION 이 있었으면 WITH ADMIN OPTION 으로)
# 영향: 지정 계정으로 하던 DBA 작업(다른 계정·객체 관리, 시스템 뷰 조회 등)이 즉시 실패
# 가이드 조치 방법: 관리자 권한을 꼭 필요한 계정에만. 필요 여부는 사람이 판단한다(진단 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 계정 이름 형식·DBA 롤 보유·Oracle 내장 계정(SYS·SYSTEM 등)·도구 접속 계정이 아님·중복 없음.
run_fix() {
    vals=$(fix_param accounts)
    if [ -z "$vals" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 D-04.accounts 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    errs=""; seen=" "; plan=""
    self=$(printf '%s' "${DB_USER:-}" | tr '[:lower:]' '[:upper:]')
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        printf '%s' "$a" | grep -qE '^[A-Za-z][A-Za-z0-9_$#]*$' || { errs="$errs / $a: 계정 이름 형식이 아님"; continue; }
        u=$(printf '%s' "$a" | tr '[:lower:]' '[:upper:]')
        case "$seen" in *" $u "*) errs="$errs / $a: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$u "
        case "$u" in SYS|SYSTEM) errs="$errs / $u: 필수 관리 계정은 대상 아님"; continue ;; esac
        [ -n "$self" ] && [ "$u" = "$self" ] && { errs="$errs / $u: 도구가 접속에 쓰는 계정"; continue; }
        st=$(oracle_query "SELECT u.oracle_maintained || '|' || NVL((SELECT admin_option FROM dba_role_privs WHERE grantee = u.username AND granted_role = 'DBA'), '-') FROM dba_users u WHERE u.username = '$u';" | tr -d ' \r' | head -n 1)
        case "$st" in
            N\|YES|N\|NO) plan="$plan$u|${st#*|} " ;;
            Y\|*) errs="$errs / $u: Oracle 내장 계정(oracle_maintained=Y)" ;;
            N\|-) errs="$errs / $u: DBA 롤이 없음" ;;
            *) errs="$errs / $u: dba_users 에 없는 계정" ;;
        esac
    done <<EOF
$vals
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi
    done_list=""; failed=""
    for p in $plan; do
        u=${p%|*}; adm=${p#*|}
        if [ "$adm" = YES ]; then fix_db_queue_rollback oracle "GRANT DBA TO \"$u\" WITH ADMIN OPTION;"
        else fix_db_queue_rollback oracle "GRANT DBA TO \"$u\";"; fi
        oracle_query "REVOKE DBA FROM \"$u\";" >/dev/null
        n=$(oracle_query "SELECT COUNT(*) FROM dba_role_privs WHERE grantee = '$u' AND granted_role = 'DBA';" | tr -d ' \r' | head -n 1)
        if [ "$n" = 0 ]; then done_list="$done_list $u"; else failed="$failed $u"; fi
    done
    FIX_EVIDENCE=$(oracle_query "SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA' ORDER BY grantee;" 2>/dev/null)
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="DBA 롤 회수 실패:$failed"
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="지정 계정에서 DBA 롤을 회수함:$done_list"
    fi
}
