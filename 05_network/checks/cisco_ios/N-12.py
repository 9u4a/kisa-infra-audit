# N-12 (상) 주기적 보안 패치 및 벤더 권고사항 적용 [Cisco IOS]
# 판단 기준(가이드 원문): 양호 = 주기적으로 패치 적용 / 취약 = 미적용
# "주기적으로 적용하는지"는 운영 이력을 알아야 하며 설정 텍스트만으로는 확인 불가 - 항상 MANUAL.
# version 라인이 있으면 최소한 현재 버전 정보를 증적으로 제공한다.
def check(ctx):
    m = ctx.search(r"^version (\d+\.\d+)")
    version = m.group(1) if m else "확인 불가"
    return {
        "status": "MANUAL",
        "detail": f"현재 IOS 버전: {version} - 최신 보안 패치 적용 및 벤더 권고사항 반영 여부는 벤더 공지와 대조하여 수동 확인 필요",
        "evidence": m.group(0) if m else "",
    }
