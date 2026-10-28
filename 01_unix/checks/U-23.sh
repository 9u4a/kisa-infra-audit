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

    # root 가 아니면 읽을 수 없는 디렉터리가 조용히 빠져 목록이 불완전해진다.
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="파일시스템 전수 검색은 root 권한이 필요함(권한 부족 시 결과가 누락되어 판정 불가)"; CHECK_EVIDENCE=""
        return
    fi
    out=$(scan_find 100 -type f \( -perm -04000 -o -perm -02000 \))
    rc=$(printf '%s\n' "$out" | sed -n 's/^__RC=//p')
    files=$(printf '%s\n' "$out" | grep -v '^__RC=' | sed '/^$/d')
    remote=$(scan_remote_mounts)
    scanned=$(scan_local_mounts | tr '\n' ' ')
    # 진단 검수 U-R10: 별도 로컬 파일시스템까지 검색하고, 시간 초과·find 오류(종료코드 2 이상)는 "없음"으로 보지 않는다.
    # find 종료코드 1 은 검색 중 사라진 임시 파일 등 비치명적 오류라(root 실행 전제) 판정은 하되 detail 에 남긴다.
    if [ -z "$files" ] && [ -n "$rc" ] && [ "$rc" -ge 2 ]; then
        CHECK_STATUS="ERROR"
        if [ "$rc" -eq 124 ]; then
            CHECK_DETAIL="파일시스템 검색이 제한 시간(${SCAN_TIMEOUT:-900}초)을 넘겨 중단됨 - 확인하지 못함 (검색 대상: $scanned)"
        else
            CHECK_DETAIL="파일시스템 검색(find)이 실패함(종료코드 $rc) - 확인하지 못함 (검색 대상: $scanned)"
        fi
        CHECK_EVIDENCE=""
        return
    fi
    note="검색 대상: ${scanned}${remote:+/ 원격·네트워크 파일시스템 미검색: $remote}"
    [ "$rc" = "1" ] && note="$note / find 일부 경로 오류(종료코드 1)"

    if [ -z "$files" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="SUID/SGID 가 설정된 파일이 존재하지 않음 ($note)"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="SUID/SGID 설정 파일 목록(최대 100건). passwd/su 등 표준 필수 바이너리를 제외하고 의심스러운 항목이 있는지 수동 검토 필요 ($note)"
        CHECK_EVIDENCE="$(printf '%s\n' "$files" | xargs ls -al 2>/dev/null)"
    fi
}
