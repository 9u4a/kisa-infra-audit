# D-26 (상) 감사 기록 설정 [Oracle] — 조치 [fix: confirm]
# 원복: 일부 — SPFILE 값은 원래대로 되돌리지만 반영하려면 인스턴스 재기동이 필요함
# checks/oracle/D-26.sh: 취약 = audit_trail=NONE. audit_trail 은 정적 파라미터라 SPFILE 값을 바꾼 뒤 재기동해야
# 반영된다 - confirm 등급에서 재기동까지 수행한다(DB 클라이언트 연결만 영향, OS 세션 영향 없음). SYSDBA 세션이
# 아니면 SHUTDOWN/STARTUP 자체가 거부되므로 OS 인증("/ as sysdba", DB_USER 미지정)으로 실행해야 한다.
# 운영 안전(1.3.1): 변경 전 SPFILE 을 PFILE 로 떠 두고(실패하면 바꾸지 않음), 원래 값을 원복 SQL 로 남기며,
# 재기동 후 인스턴스가 열리지 않으면 PFILE 로 SPFILE 을 되돌리고 다시 기동한다(oracle_restart_or_recover).
run_fix() {
    orig=$(oracle_query "SELECT value FROM v\$parameter WHERE name = 'audit_trail';" | tr -d ' \r')
    if ! oracle_pfile_backup "D-26"; then
        FIX_STATUS="ERROR"; FIX_DETAIL="변경 전 SPFILE 백업(CREATE PFILE)에 실패해 변경하지 않음 - 재기동 실패 시 복구할 수 없기 때문(SYSDBA/OS 인증으로 실행 필요)"; FIX_EVIDENCE=""
        return
    fi
    fix_db_queue_rollback "oracle" "ALTER SYSTEM SET audit_trail = ${orig:-NONE} SCOPE=SPFILE;"
    out=$(oracle_query "ALTER SYSTEM SET audit_trail = DB SCOPE=SPFILE;" 2>&1)

    oracle_restart_or_recover
    case "$DB_RESTART_RESULT" in
        ok)
            val=$(oracle_query "SELECT value FROM v\$parameter WHERE name = 'audit_trail';" | tr -d ' \r')
            if [ "$val" = "NONE" ] || [ -z "$val" ]; then
                FIX_STATUS="ERROR"; FIX_DETAIL="재기동했으나 audit_trail 이 여전히 NONE: $out"
            else
                FIX_STATUS="APPLIED"; FIX_DETAIL="audit_trail=DB 로 설정하고 재기동해 적용함(변경 전 ${orig:-NONE}, 현재 $val, PFILE 백업: $ORACLE_PFILE_BACKUP)"
            fi
            FIX_EVIDENCE="audit_trail=$val" ;;
        reverted)
            FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 인스턴스가 열리지 않아 변경 전 PFILE 로 SPFILE 을 되돌리고 다시 기동함(서비스 복구 확인됨): $out"; FIX_EVIDENCE="" ;;
        *)
            FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 인스턴스가 열리지 않고 자동 복구도 확인하지 못함 - 즉시 수동 조치 필요(STARTUP PFILE='$ORACLE_PFILE_BACKUP' 후 CREATE SPFILE FROM PFILE)"; FIX_EVIDENCE="" ;;
    esac
}
