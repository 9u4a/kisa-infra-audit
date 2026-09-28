# U-55 (중) FTP 계정 shell 제한
# 판단 기준(가이드 원문): 양호 = ftp 계정에 /bin/false(/sbin/nologin) 쉘 부여 / 취약 = 미부여
# 전 Unix 계열 공통 로직. ftp 계정이 없으면 NA.

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    entry=$(grep '^ftp:' "$passwd_file" 2>/dev/null)
    if [ -z "$entry" ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="ftp 계정이 존재하지 않음"
        CHECK_EVIDENCE=""
        return
    fi

    shell=$(printf '%s' "$entry" | awk -F: '{print $NF}')
    CHECK_EVIDENCE="$entry"
    case "$shell" in
        */nologin|/bin/false)
            CHECK_STATUS="GOOD"
            CHECK_DETAIL="ftp 계정에 ${shell} 쉘이 부여되어 있음"
            ;;
        *)
            CHECK_STATUS="VULN"
            CHECK_DETAIL="ftp 계정의 쉘이 ${shell} 로, /bin/false 또는 nologin 이 아님"
            ;;
    esac
}
