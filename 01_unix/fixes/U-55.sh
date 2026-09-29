# U-55 (중) FTP 계정 shell 제한 — 조치
run_fix() {
    passwd_file="/etc/passwd"
    entry=$(grep '^ftp:' "$passwd_file" 2>/dev/null)
    if [ -z "$entry" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="ftp 계정이 없어 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    nologin=$(command -v nologin 2>/dev/null || echo /sbin/nologin)
    fix_backup "$passwd_file"
    if usermod -s "$nologin" ftp 2>/dev/null; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="ftp 계정의 쉘을 ${nologin} 로 변경함"; FIX_EVIDENCE="$(grep '^ftp:' "$passwd_file")"
    else
        FIX_STATUS="FAILED"; FIX_DETAIL="usermod 실행 실패"; FIX_EVIDENCE=""
    fi
}
