# U-56 (하) FTP 서비스 접근 제어 설정 — 조치
# 자동화 범위: 가장 보편적인 메커니즘인 ftpusers 에 최소 root 를 등록해 "접근 제어가 설정된
# 상태"로 만든다(U-57 root 차단과 동일 효과, 이 카테고리 항목들의 기본 안전선).
run_fix() {
    applied=""
    for f in /etc/ftpusers /etc/ftpd/ftpusers; do
        [ -f "$f" ] || continue
        grep -qE '^[[:space:]]*root[[:space:]]*$' "$f" || { fix_backup "$f"; printf 'root\n' >> "$f"; applied="$applied $f"; }
    done
    if [ -z "$applied" ] && [ ! -f /etc/ftpusers ] && [ ! -f /etc/ftpd/ftpusers ]; then
        if [ -f /etc/vsftpd.conf ] || [ -f /etc/vsftpd/vsftpd.conf ] || [ -f /etc/proftpd.conf ] || [ -f /etc/proftpd/proftpd.conf ]; then
            fix_backup /etc/ftpusers
            printf 'root\n' > /etc/ftpusers
            applied="/etc/ftpusers(신규 생성)"
        fi
    fi
    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="FTP 미사용 또는 이미 접근 제어가 설정되어 있어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="ftpusers 에 root 를 등록해 접근 제어를 설정함:$applied"; FIX_EVIDENCE="$applied"
    fi
}
