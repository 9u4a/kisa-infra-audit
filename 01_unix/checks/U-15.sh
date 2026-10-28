# U-15 (상) 파일 및 디렉터리 소유자 설정
# 판단 기준(가이드 원문): 양호 = 소유자가 존재하지 않는 파일 및 디렉터리가 없는 경우
#                        취약 = 존재하는 경우
# 전 Unix 계열 공통 로직. / 와 별도 로컬 파일시스템을 각각 -xdev 로 검사(lib/common.sh scan_find).
# 대상 파일 수가 많은 시스템에서는 시간이 걸릴 수 있음.

run_check() {
    if ! command -v find >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="find 명령을 사용할 수 없음"
        CHECK_EVIDENCE=""
        return
    fi

    # root 가 아니면 읽을 수 없는 디렉터리가 조용히 빠져 "없음 = 양호" 로 오인된다.
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="파일시스템 전수 검색은 root 권한이 필요함(권한 부족 시 결과가 누락되어 판정 불가)"; CHECK_EVIDENCE=""
        return
    fi
    # 운영 I/O 와 경쟁하지 않도록 낮은 우선순위로 실행(lib/common.sh low_prio)
    out=$(scan_find 50 \( -nouser -o -nogroup \))
    rc=$(printf '%s\n' "$out" | sed -n 's/^__RC=//p')
    result=$(printf '%s\n' "$out" | grep -v '^__RC=' | sed '/^$/d')
    remote=$(scan_remote_mounts)
    scanned=$(scan_local_mounts | tr '\n' ' ')
    # 진단 검수 U-R10: 별도 로컬 파일시스템까지 검색하고, 시간 초과·find 오류(종료코드 2 이상)는 "없음"으로 보지 않는다.
    # find 종료코드 1 은 검색 중 사라진 임시 파일 등 비치명적 오류라(root 실행 전제) 판정은 하되 detail 에 남긴다.
    if [ -z "$result" ] && [ -n "$rc" ] && [ "$rc" -ge 2 ]; then
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

    if [ -z "$result" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="소유자 또는 그룹이 존재하지 않는 파일/디렉터리가 없음 ($note)"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="소유자 또는 그룹이 존재하지 않는 파일/디렉터리가 존재함 (최대 50건 표시)"
        CHECK_EVIDENCE="$result"
    fi
}
