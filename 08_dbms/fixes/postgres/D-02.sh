# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용 [PostgreSQL] — 조치 [fix: param]
# 값: accounts=잠글 역할(로그인 가능 역할 이름, 쉼표 구분) - 진단 증적의 역할 목록 중 운영자가 불필요하다고 판단한 것
# 변경: 지정 역할 ALTER ROLE ... NOLOGIN (삭제하지 않음 - 원복 시 LOGIN)
# 영향: 지정 역할로 하던 DB 접속(애플리케이션·배치)이 즉시 거부됨
# 가이드 조치 방법: 불필요 계정 삭제 또는 잠금. "불필요" 판단은 사람이 한다(진단 MANUAL) - 1.7.0 값 지정 조치로 정책 값의 역할만 잠근다.
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 역할 이름 형식(영문·숫자·_)·pg_roles 에 있고 로그인 가능·postgres·도구 접속 역할이
# 아님·중복 없음.
run_fix() {
    vals=$(fix_param accounts)
    if [ -z "$vals" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 D-02.accounts 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    command -v psql >/dev/null 2>&1 || { FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""; return; }
    errs=""; seen=" "
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        case "$seen" in *" $r "*) errs="$errs / $r: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$r "
        printf '%s' "$r" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || { errs="$errs / $r: 역할 이름 형식이 아님(영문·숫자·_)"; continue; }
        [ "$r" = postgres ] && { errs="$errs / $r: 기본 관리자 역할은 잠그지 않음"; continue; }
        [ "$r" = "${DB_USER:-postgres}" ] && { errs="$errs / $r: 도구가 접속에 쓰는 역할"; continue; }
        st=$(psql_query "SELECT rolcanlogin FROM pg_roles WHERE rolname = '$r';") || { errs="$errs / $r: 역할 조회 실패"; continue; }
        case "$st" in t) ;; f) errs="$errs / $r: 이미 로그인 불가(NOLOGIN)" ;; *) errs="$errs / $r: pg_roles 에 없는 역할" ;; esac
    done <<EOF
$vals
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi
    done_list=""; failed=""
    for r in $seen; do
        fix_db_queue_rollback postgres "ALTER ROLE \"$r\" LOGIN;"
        if psql_query "ALTER ROLE \"$r\" NOLOGIN;" >/dev/null && [ "$(psql_query "SELECT rolcanlogin FROM pg_roles WHERE rolname = '$r';")" = f ]; then
            done_list="$done_list $r"
        else
            failed="$failed $r"
        fi
    done
    FIX_EVIDENCE=$(psql_query "SELECT rolname, rolcanlogin FROM pg_roles ORDER BY rolname;" 2>/dev/null)
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="역할 잠금 실패:$failed"
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="지정 역할을 로그인 불가로(NOLOGIN):$done_list"
    fi
}
