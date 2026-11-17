# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용 [PostgreSQL] — 조치 [fix: param]
# 값: accounts=SUPERUSER 를 회수할 역할(쉼표 구분) - 진단 증적의 rolsuper 역할 중 불필요한 것
# 변경: 지정 역할 ALTER ROLE ... NOSUPERUSER (원복 시 SUPERUSER)
# 영향: 지정 역할로 하던 슈퍼유저 작업(확장 설치·다른 역할 관리·서버 설정 변경 등)이 즉시 실패
# 가이드 조치 방법: 관리자 권한을 꼭 필요한 계정에만. 필요 여부는 사람이 판단한다(진단 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 역할 이름 형식·지금 rolsuper·postgres·도구 접속 역할이 아님·중복 없음.
run_fix() {
    vals=$(fix_param accounts)
    if [ -z "$vals" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 D-04.accounts 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    command -v psql >/dev/null 2>&1 || { FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""; return; }
    errs=""; seen=" "
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        case "$seen" in *" $r "*) errs="$errs / $r: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$r "
        printf '%s' "$r" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || { errs="$errs / $r: 역할 이름 형식이 아님(영문·숫자·_)"; continue; }
        [ "$r" = postgres ] && { errs="$errs / $r: 기본 관리자 역할은 대상 아님"; continue; }
        [ "$r" = "${DB_USER:-postgres}" ] && { errs="$errs / $r: 도구가 접속에 쓰는 역할"; continue; }
        st=$(psql_query "SELECT rolsuper FROM pg_roles WHERE rolname = '$r';") || { errs="$errs / $r: 역할 조회 실패"; continue; }
        case "$st" in t) ;; f) errs="$errs / $r: SUPERUSER 가 아님" ;; *) errs="$errs / $r: pg_roles 에 없는 역할" ;; esac
    done <<EOF
$vals
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi
    done_list=""; failed=""
    for r in $seen; do
        fix_db_queue_rollback postgres "ALTER ROLE \"$r\" SUPERUSER;"
        if psql_query "ALTER ROLE \"$r\" NOSUPERUSER;" >/dev/null && [ "$(psql_query "SELECT rolsuper FROM pg_roles WHERE rolname = '$r';")" = f ]; then
            done_list="$done_list $r"
        else
            failed="$failed $r"
        fi
    done
    FIX_EVIDENCE=$(psql_query "SELECT rolname FROM pg_roles WHERE rolsuper ORDER BY rolname;" 2>/dev/null)
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="SUPERUSER 회수 실패:$failed"
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="지정 역할의 SUPERUSER 를 회수함(NOSUPERUSER):$done_list"
    fi
}
