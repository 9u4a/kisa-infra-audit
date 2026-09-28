# U-20 (상) /etc/(x)inetd.conf 파일 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 소유자 root, 권한 600 이하 / 취약 = 그 외
# 자동화 범위: xinetd.conf/inetd.conf 가 존재하면 그것을 판정. 없고(대부분의 최신 배포판)
#             systemd 만 사용 중이면 /etc/systemd/system.conf 를 대체 판정 대상으로 사용.

run_check() {
    if [ -f /etc/xinetd.conf ]; then
        check_owner_perm "/etc/xinetd.conf" "root" 600
        base_status=$CHECK_STATUS; base_detail=$CHECK_DETAIL; base_evd=$CHECK_EVIDENCE
        bad_d=$(find /etc/xinetd.d -maxdepth 1 -type f \( ! -user root -o -perm -0022 \) 2>/dev/null)
        if [ -n "$bad_d" ]; then
            CHECK_STATUS="VULN"
            CHECK_DETAIL="$base_detail / /etc/xinetd.d 내 기준 미달 파일 존재"
            CHECK_EVIDENCE="$base_evd
$bad_d"
        else
            CHECK_STATUS=$base_status; CHECK_DETAIL=$base_detail; CHECK_EVIDENCE=$base_evd
        fi
        return
    fi

    if [ -f /etc/inetd.conf ]; then
        check_owner_perm "/etc/inetd.conf" "root" 600
        return
    fi

    if [ -f /etc/systemd/system.conf ]; then
        check_owner_perm "/etc/systemd/system.conf" "root" 600
        CHECK_DETAIL="(x)inetd 미사용(systemd 기반) — 대체 판정 대상 /etc/systemd/system.conf: $CHECK_DETAIL"
        return
    fi

    CHECK_STATUS="NA"
    CHECK_DETAIL="(x)inetd 및 systemd 설정 파일 모두 존재하지 않음"
    CHECK_EVIDENCE=""
}
