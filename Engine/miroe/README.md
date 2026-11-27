# miroe

Miro의 차세대 엔진이에요. 애플 실리콘 전용 ARM64 네이티브 Wine + FEX, 그래픽은 Mullion이에요. 연구 단계라서 아직 Miro 앱에는 들어 있지 않아요.

- 성과와 계획 요약: [`../../RESEARCH.md`](../../RESEARCH.md)
- 패치: [`patches/`](patches), 실습실 스크립트: [`scripts/`](scripts), 측정 도구: [`tools/`](tools), 고정한 소스: [`sources.conf`](sources.conf)
- 상세 자료: [연구 기록](docs/research-log.md), [기반 구성 검토](docs/base.md), [문제 목록과 선행 기술 조사](docs/problems.md), [초기 측정](docs/early-measurements.md)

## Miro 앱에서 쓰기 (실험)

`Scripts/install_miroe_engine.sh`로 실습실에서 빌드한 엔진을 Miro의 엔진 폴더에 넣으면, Miro의 설정 → 호환 레이어에 **miroe (실험)** 이 나타나요. 'Windows 환경 준비'를 누른 뒤 게임 설정 → 호환 엔진에서 게임마다 고를 수 있어요.

- 64비트 프로그램만 돼요(서명 권한이 없는 dev 엔진). 32비트 게임은 실행 전에 안내해요.
- 자동으로는 고르지 않고, 실패해도 다른 엔진으로 넘어가지 않아요. 라이브러리 자동 설치도 아직 하지 않아요.
- 아직 내려받을 수 없어요. 서명된 엔진은 개발자 계정에 등록한 Mac에서만 돌아서, 공개 배포 방법은 아직 정하지 않았어요.
