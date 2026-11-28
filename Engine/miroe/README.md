# miroe

Miro의 차세대 엔진이에요. 애플 실리콘 전용 ARM64 네이티브 Wine + FEX, 그래픽은 Mullion이에요. 연구 단계라서 아직 Miro 앱에는 들어 있지 않아요.

- 성과와 계획 요약: [`../../RESEARCH.md`](../../RESEARCH.md)
- 패치: [`patches/`](patches), 실습실 스크립트: [`scripts/`](scripts), 측정 도구: [`tools/`](tools), 고정한 소스: [`sources.conf`](sources.conf)
- 상세 자료: [연구 기록](docs/research-log.md), [기반 구성 검토](docs/base.md), [문제 목록과 선행 기술 조사](docs/problems.md), [초기 측정](docs/early-measurements.md)

## Miro 앱에서 쓰기

`Scripts/install_miroe_engine.sh`로 실습실에서 빌드한 엔진을 Miro의 엔진 폴더에 넣어요. 2026-11-28부터 Miro는 모든 게임과 Steam을 miroe에서 돌리고, 그래픽은 자동으로 골라요(DirectX 10~12 Mullion, 1~9 WineD3D). 예전 엔진의 Steam 폴더와 세이브는 그대로 두고 miroe에서 이어서 써요(`docs/base.md` 9장).

- 엔진: 서명된 upstream ARM64 Wine + FEX + Mullion + MUMA. 64비트와 32비트 게임이 돼요(DirectX 12는 64비트만). 만드는 순서: `scripts/build-wine-upstream.sh` → `scripts/sign-engine.sh` → `scripts/build-mullion-upstream.sh` → `Scripts/install_miroe_engine.sh`.
- 그래픽: Direct3D 10~12는 Mullion + MUMA, Direct3D 1~9와 DirectDraw는 Wine의 WineD3D(OpenGL), Vulkan은 MoltenVK예요. DXVK(D3D8·9)는 빌드되지만 MoltenVK에 필수 기능 다섯 개가 없어서 아직 넣지 않았어요([기반 검토 8절](docs/base.md)).
- 2026-11-28부터 HTTPS(GnuTLS)와 Vulkan(MoltenVK)이 돼요. 필요한 라이브러리는 설치 스크립트가 엔진 안에 넣고, 라이선스는 `miro/licenses`에 같이 둬요.
- Windows Steam이 miroe에서 돌아요(Mullion 패치 0003: 다른 프로세스 창에 그리는 Chromium 화면을 보여 줌). 클릭·키 입력·한글 조합(Wine 패치 `patches/wine/0001`)을 확인했고, 실제 계정으로 로그인해 상점까지 떠요.
- 기본 글꼴은 Noto Sans CJK KR(SIL OFL 1.1)이에요. 엔진의 `miro/fonts`에 들어 있고 Miro가 각 C: 드라이브에 넣어요.
- 예전 64비트 전용 엔진으로 만든 Windows 환경은 'Windows 환경 준비'를 한 번 더 누르면 32비트 지원이 더해져요.
- 자동으로는 고르지 않고, 실패해도 다른 엔진으로 넘어가지 않아요. 라이브러리 자동 설치도 아직 하지 않아요.
- 아직 내려받을 수 없어요. 서명된 엔진은 개발자 계정에 등록한 Mac에서만 돌아서, 공개 배포 방법은 아직 정하지 않았어요.
