# D-12 (상) 안전한 리스너 비밀번호 설정 및 사용 [Oracle] — 조치 [fix: auto]
# checks/oracle/D-12.sh 와 동일하게 12c R2 이상은 이 기능 자체가 없어(가이드 원문 명시) NA.
# 12c R2 미만에서만 listener.ora 에 무작위 비밀번호를 설정하고 lsnrctl reload 로 즉시 반영한다
# (reload 는 기존 DB 세션 연결에는 영향 없음 - 리스너 프로세스만 설정을 다시 읽음).
run_fix() {
    # 1.4.0(D-C2): 예전에는 12 이상이면 NA 라, check 가 취약으로 보는 12c Release 1(12.1)에서 조치가 "해당 없음"으로
    # 끝났다(check 는 12.1 을 지원 버전으로 봄 - 진단 검수 D-R11). check 와 같은 기준(12.2 이상만 NA)으로 맞췄다.
    ver=$(oracle_query "SELECT version FROM v\$instance;" | tr -d ' \t\r' | awk 'NF' | head -n 1)
    _major=$(printf '%s' "$ver" | awk -F. '{print $1+0}')
    _minor=$(printf '%s' "$ver" | awk -F. '{print $2+0}')
    if [ -n "$ver" ] && { [ "$_major" -gt 12 ] || { [ "$_major" -eq 12 ] && [ "$_minor" -ge 2 ]; }; }; then
        FIX_STATUS="NA"; FIX_DETAIL="Oracle 12c Release 2 이상은 Listener 비밀번호 설정을 지원하지 않음(해당 없음)"; FIX_EVIDENCE=""
        return
    fi
    f=$(oracle_listener_ora)
    if [ -z "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="listener.ora 파일을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    newpass=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-20)
    [ -z "$newpass" ] && newpass="Ch$(date +%s)Xz9Aa1"

    fix_backup "$f"
    printf '\nPASSWORDS_LISTENER = (%s)\n' "$newpass" >> "$f"

    reloaded=0
    if command -v lsnrctl >/dev/null 2>&1; then
        lsnrctl reload >/dev/null 2>&1 && reloaded=1
    fi

    FIX_STATUS="APPLIED"
    FIX_DETAIL="$f 에 리스너 비밀번호를 설정함(원문은 증적에 남기지 않음)$([ "$reloaded" -eq 1 ] && echo ' - lsnrctl reload 로 즉시 반영함' || echo ' - lsnrctl 을 찾지 못해 수동 reload 필요')"
    FIX_EVIDENCE=""
}
