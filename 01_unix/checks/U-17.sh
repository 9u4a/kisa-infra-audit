# U-17 (상) 시스템 시작 스크립트 권한 설정
# 판단 기준(가이드 원문): 양호 = 소유자 root, 일반 사용자 쓰기 권한 없음 / 취약 = 그 외
# 자동화 범위: systemd 기반(rhel/debian 최신 배포판) /etc/systemd/system/* 만 판정.
# 레거시 init(/etc/rc.d, /etc/init.d)만 있는 시스템은 MANUAL.

run_check() {
    systemd_dir="/etc/systemd/system"
    if [ -d "$systemd_dir" ]; then
        violations=$(find -L "$systemd_dir" -maxdepth 2 -type f \( ! -user root -o -perm -0022 \) 2>/dev/null | head -n 50)
        if [ -z "$violations" ]; then
            CHECK_STATUS="GOOD"
            CHECK_DETAIL="$systemd_dir 하위 시작 스크립트(유닛 파일)가 root 소유이며 그룹/기타 쓰기 권한이 없음"
            CHECK_EVIDENCE=""
        else
            CHECK_STATUS="VULN"
            CHECK_DETAIL="root 소유가 아니거나 그룹/기타 쓰기 권한이 부여된 시작 스크립트(유닛 파일)가 존재함 (최대 50건)"
            CHECK_EVIDENCE="$violations"
        fi
        return
    fi

    for legacy in /etc/rc.d /etc/init.d; do
        if [ -d "$legacy" ]; then
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="레거시 init 방식($legacy) 감지됨 — 0.2.0 후속 작업에서 자동 판정 로직 추가 예정"
            CHECK_EVIDENCE="$(ls -al "$legacy" 2>/dev/null | head -n 30)"
            return
        fi
    done

    CHECK_STATUS="ERROR"
    CHECK_DETAIL="시스템 시작 스크립트 디렉터리를 찾을 수 없음"
    CHECK_EVIDENCE=""
}
