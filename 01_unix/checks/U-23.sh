# U-23 (상) SUID, SGID, Sticky bit 설정 파일 점검
# 판단 기준(가이드 원문): 양호 = 주요 실행 파일에 SUID/SGID 설정이 없는 경우
#                        취약 = 설정되어 있는 경우
# 실제로는 /usr/bin/passwd, /usr/bin/su 등 정상 운영에 SUID 가 반드시 필요한 표준 바이너리가
# 모든 Unix 시스템에 존재하므로, 단순 "존재=취약"으로 자동 판정하면 오탐이 발생한다.
# 자동화 범위: 전 Unix 계열 공통 — SUID/SGID 파일 목록을 수집해 사람이 검토하도록 MANUAL 로 제공한다.

run_check() {
    if ! command -v find >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="find 명령을 사용할 수 없음"
        CHECK_EVIDENCE=""
        return
    fi

    files=$(find / -xdev -type f \( -perm -04000 -o -perm -02000 \) 2>/dev/null | head -n 100)

    if [ -z "$files" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="SUID/SGID 가 설정된 파일이 존재하지 않음"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="SUID/SGID 설정 파일 목록(최대 100건). passwd/su 등 표준 필수 바이너리를 제외하고 의심스러운 항목이 있는지 수동 검토 필요"
        CHECK_EVIDENCE="$(printf '%s\n' "$files" | xargs ls -al 2>/dev/null)"
    fi
}
