# D-19 (상) OS_ROLES, REMOTE_OS_AUTHENTICATION, REMOTE_OS_ROLES를 FALSE로 설정 [Oracle] — 조치 [fix: confirm]
# 원복: 일부 — SPFILE 값은 원래대로 되돌리지만 반영하려면 인스턴스 재기동이 필요함
# 세 파라미터 모두 정적(static) 파라미터라 SPFILE 값을 바꾼 뒤 인스턴스를 재기동해야 반영된다 - confirm 등급에서
# 재기동까지 수행한다(DB 클라이언트 연결만 영향, 이 스크립트의 OS 세션에는 영향 없음).
# 운영 안전(1.3.1):
#  - 변경 전 SPFILE 을 PFILE 로 떠 두고(실패하면 아무것도 바꾸지 않음), 원래 값을 조회해 원복 SQL 로 남긴다.
#  - 재기동 후 인스턴스가 열리지 않으면 PFILE 로 기동해 SPFILE 을 되돌리고 다시 기동한다(oracle_restart_or_recover).
# 주의(Docker 23ai/26ai 실기 테스트로 확인): remote_os_authent 는 최신 버전에서 obsolete(ORA-02065)라 v$parameter
# 에도 없다 - 세 ALTER SYSTEM 을 각각 실행해 한 파라미터의 실패가 나머지를 막지 않게 한다.
run_fix() {
    orig=$(oracle_query "SELECT name || '=' || value FROM v\$parameter WHERE name IN ('os_roles','remote_os_authent','remote_os_roles') ORDER BY name;" | tr -d ' \r' | grep '=')
    if ! oracle_pfile_backup "D-19"; then
        FIX_STATUS="ERROR"; FIX_DETAIL="변경 전 SPFILE 백업(CREATE PFILE)에 실패해 변경하지 않음 - 재기동 실패 시 복구할 수 없기 때문(SYSDBA/OS 인증으로 실행 필요)"; FIX_EVIDENCE=""
        return
    fi
    # 원복 SQL 은 SPFILE 의 원래 상태 기준(1.4.0 D-C5): 값이 지정돼 있지 않던(기본값) 파라미터는 RESET 으로 되돌린다 - 예전에는
    # 실행 값을 SET 해 SPFILE 에 원래 없던 항목이 남았다. v$spparameter 조회에 실패하면 예전 방식(실행 값 SET)으로 둔다.
    spec=$(oracle_query "SELECT name || '=' || isspecified FROM v\$spparameter WHERE name IN ('os_roles','remote_os_authent','remote_os_roles') AND (sid = '*' OR sid IS NULL);" | tr -d ' \r' | grep '=')
    for kv in $orig; do
        _p=${kv%%=*}
        case "
$spec
" in
            *"
$_p=FALSE
"*) fix_db_queue_rollback "oracle" "ALTER SYSTEM RESET $_p SCOPE=SPFILE;" ;;
            *) fix_db_queue_rollback "oracle" "ALTER SYSTEM SET $_p = ${kv#*=} SCOPE=SPFILE;" ;;
        esac
    done

    o1=$(oracle_query "ALTER SYSTEM SET os_roles = FALSE SCOPE=SPFILE;" 2>&1)
    o2=$(oracle_query "ALTER SYSTEM SET remote_os_authent = FALSE SCOPE=SPFILE;" 2>&1)
    o3=$(oracle_query "ALTER SYSTEM SET remote_os_roles = FALSE SCOPE=SPFILE;" 2>&1)

    oracle_restart_or_recover
    case "$DB_RESTART_RESULT" in
        ok)
            val=$(oracle_query "SELECT name, value FROM v\$parameter WHERE name IN ('os_roles','remote_os_authent','remote_os_roles') ORDER BY name;")
            if printf '%s\n' "$val" | grep -qi TRUE; then
                FIX_STATUS="ERROR"; FIX_DETAIL="재기동했으나 일부 값이 여전히 TRUE: $val"
            else
                FIX_STATUS="APPLIED"; FIX_DETAIL="SPFILE 값을 FALSE 로 설정하고 재기동해 적용함(변경 전: $(printf '%s' "$orig" | tr '\n' ' '), PFILE 백업: $ORACLE_PFILE_BACKUP)"
            fi
            FIX_EVIDENCE="$val" ;;
        reverted)
            FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 인스턴스가 열리지 않아 변경 전 PFILE 로 SPFILE 을 되돌리고 다시 기동함(서비스 복구 확인됨): $o1 / $o2 / $o3"; FIX_EVIDENCE="" ;;
        *)
            FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 인스턴스가 열리지 않고 자동 복구도 확인하지 못함 - 즉시 수동 조치 필요(STARTUP PFILE='$ORACLE_PFILE_BACKUP' 후 CREATE SPFILE FROM PFILE)"; FIX_EVIDENCE="" ;;
    esac
}
