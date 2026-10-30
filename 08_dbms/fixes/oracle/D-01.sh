# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [Oracle] — 조치 [fix: confirm]
# 원복: 가능 — 잠근 계정을 다시 UNLOCK 함
# checks/oracle/D-01.sh 와 같은 범위(초기 비밀번호 그대로이고 OPEN 인 계정 - DBA_USERS_WITH_DEFPWD)를 잠근다(비밀번호를
# 추측해 바꾸는 대신 계정 잠금 - 가이드가 제시한 두 대안 중 스크립트가 안전하게 할 수 있는 쪽).
# SYSTEM 은 필수 관리 계정이라 잠그지 않는다(lockout 방지) - 초기 비밀번호 그대로인 SYSTEM 이 있으면 비밀번호 변경이
# 필요하다고 보고하고(PARTIAL/MANUAL, fix.sh 는 원복하지 않음) 나머지만 잠근다(1.4.0 D-C1: 예전에는 OPEN 인 SYSTEM 을
# 취약으로 판정하면서 조치는 건너뛰어 재검증 VULN → 원복으로 끝났다).
run_fix() {
    out=$(oracle_query "SELECT u.username FROM dba_users u WHERE u.account_status = 'OPEN' AND u.username IN (SELECT d.username FROM dba_users_with_defpwd d) ORDER BY u.username;")
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="Oracle 연결/쿼리 실패: $out"; FIX_EVIDENCE=""
        return
    fi
    if [ -z "$(printf '%s' "$out" | tr -d ' \r\n')" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="초기 비밀번호 그대로인 OPEN 계정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""; failed=""; manual=""
    old_ifs=$IFS; IFS='
'
    for u in $out; do
        IFS=$old_ifs
        u=$(printf '%s' "$u" | tr -d ' \r')
        [ -z "$u" ] && { IFS='
'; continue; }
        case "$u" in
            *[!A-Z0-9_\$\#]*) failed="$failed $u(처리할 수 없는 계정 이름)"; IFS='
'; continue ;;
        esac
        if [ "$u" = "SYSTEM" ]; then
            manual="$manual $u"
            IFS='
'; continue
        fi
        fix_db_queue_rollback "oracle" "ALTER USER \"$u\" ACCOUNT UNLOCK;"
        if oracle_query "ALTER USER \"$u\" ACCOUNT LOCK;" >/dev/null 2>&1; then
            applied="$applied $u"
        else
            failed="$failed $u($(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null))"
        fi
        IFS='
'
    done
    IFS=$old_ifs

    FIX_EVIDENCE=""
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="${applied:+잠금:$applied / }잠금 실패:$failed"
    elif [ -n "$manual" ]; then
        if [ -n "$applied" ]; then FIX_STATUS="PARTIAL"; else FIX_STATUS="MANUAL"; fi
        FIX_DETAIL="${applied:+초기 비밀번호 그대로인 기본 계정을 잠금함:$applied / }수동 조치 필요 -$manual 은 필수 관리 계정이라 잠그지 않음: 비밀번호를 변경할 것(ALTER USER SYSTEM IDENTIFIED BY <새 비밀번호>)"
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="초기 비밀번호 그대로인 기본 계정을 잠금함:$applied"
    fi
}
