# WEB-25 (상) 주기적 보안 패치 및 벤더 권고사항 적용
# 판단 기준(가이드 원문): 양호 = 최신 보안 패치 적용 + 패치 정책 수립·이행
#                        취약 = 미적용 또는 정책 미수립
# "정책 수립·최신 여부"는 운영 정책·벤더 배포 현황 대조가 필요해 자동 판정이 불가능하다.
# 감지된 엔진의 버전 정보를 근거로 MANUAL 로 제공한다.

run_check() {
    detect_web_engines
    if [ -z "$WEB_ENGINES" ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="설치된 웹 엔진을 찾지 못함"; CHECK_EVIDENCE=""
        return
    fi

    evidence=""
    case " $WEB_ENGINES " in *" apache "*)
        v=$( (httpd -v 2>/dev/null || apache2 -v 2>/dev/null) | head -n1)
        evidence="$evidence
[Apache] $v"
    esac
    case " $WEB_ENGINES " in *" nginx "*)
        v=$(nginx -v 2>&1 | head -n1)
        evidence="$evidence
[Nginx] $v"
    esac
    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        v="확인 실패"
        [ -f "$home/lib/catalina.jar" ] && v=$(find "$home/lib" -name 'catalina.jar' -exec sh -c 'unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null' _ {} \; | grep -i 'Implementation-Version' | head -n1)
        evidence="$evidence
[Tomcat] CATALINA_HOME=$home $v"
    esac

    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="최신 패치 적용 여부(벤더 배포 현황 대조) 및 패치 관리 절차 수립·이행 여부는 자동 판정할 수 없음. 감지된 버전 정보를 근거로 수동 확인 필요"
    CHECK_EVIDENCE="$evidence"
}
