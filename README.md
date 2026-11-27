<div align="center">

# Miro ✦

**Windows 게임과 프로그램을, 호환성 걱정 없이 Mac에서.**

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/boartat/Miro)](https://github.com/boartat/Miro/releases/latest)
![Apple Silicon · macOS 14+](https://img.shields.io/badge/Apple%20Silicon-macOS%2014%2B-lightgrey)
![miroe: ARM64 Wine · FEX · Mullion](https://img.shields.io/badge/miroe-ARM64%20Wine%20%C2%B7%20FEX%20%C2%B7%20Mullion-8a2be2)

**[⬇︎ 다운로드](https://github.com/boartat/Miro/releases/latest/download/Miro.zip)** · [성과](#성과) · [비교](#다른-프로젝트와-비교) · [연구 요약](RESEARCH.md) · [English](#english)

</div>

**Miro**는 Apple 실리콘 Mac용 무료 Windows 게임·프로그램 런처예요. 게임 폴더를 끌어다 놓고 플레이를 누르면, 알맞은 Wine 엔진과 그래픽 방식을 골라서 실행해요.

**miroe**는 Miro의 차세대 엔진이에요. 애플 실리콘 전용 ARM64 네이티브 Wine + FEX에 오픈소스 DirectX 12([Mullion](https://github.com/dttdrv/mullion))를 얹고, Mac용 Wine에 남은 병목을 직접 고치고 있어요. **[Claude](https://claude.ai)(AI)와 함께 연구 중**이고, 코드와 측정 결과는 모두 공개해요.

![Miro 홈 화면](docs/screenshots/01-home.png)

## 성과

| 고친 것 | 결과 |
| --- | --- |
| **그래픽 메모리 누수** (MUMA, [DXMT #260](https://github.com/3Shain/dxmt/issues/260)) | 동적 버퍼 **−67%**, 동적 텍스처 **−80%**, 게임형 테스트 교전 뒤 **−48~59%**. 속도 손해 없음 |
| **32비트 게임 슬라이드쇼** (W1, [DXMT #161](https://github.com/3Shain/dxmt/issues/161), Rosetta) | 프레임 **57배** (35 → 1,997) |
| **D3DMetal 없이 DirectX 12** | ARM64에서 기능 수준 **12_2**, 셰이더 모델 **6.7**. 셰이더 테스트 모두 정확 |
| **한중일 글자 깨짐** | 다운로드 없이 **−94%** (140 → 8) |
| **그래픽 효율** (Miro 1.1+) | 같은 장면에서 DXMT가 DXVK보다 GPU 사용 **약 −70%** |

M4 Pro, macOS 27에서 직접 만든 테스트 프로그램으로 잰 값이에요(실제 게임과 다를 수 있어요). 원인과 방법은 **[RESEARCH.md](RESEARCH.md)** 에 짧게 정리해 뒀어요.

## 다른 프로젝트와 비교

2026-11-27 기준이에요.

| | Miro 1.2 | **miroe** (연구 중) | CrossOver | Whisky | Highball | Hadron | MetalSharp |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 가격 | 무료 | 무료 | 유료 | 무료 | 무료 | 무료 | 무료 |
| 라이선스 | GPL-3.0 | GPL-3.0 (패치 LGPL) | 상용 | GPL-3.0 | GPL-3.0 | BSD-3 | AGPL-3.0 |
| CPU 경로 | Rosetta | **ARM64 + FEX** | 26: Rosetta, 27 프리뷰: ARM64 + FEX | Rosetta | Rosetta | ARM64 + FEX | ARM64 + FEX |
| DirectX 12 | D3DMetal | **Mullion (오픈소스)** | D3DMetal | D3DMetal | D3DMetal | vkd3d-proton + KosmicKrisp | Mullion |
| 그래픽 메모리 회수 (MUMA) | — | **있음** | — | — | — | — | — |
| 상태 | 배포 중 | 연구 중 | 배포 중 | 개발 중단 (2025) | 배포 중 | 배포 중 | 배포 중 |

MUMA가 고친 문제(#260)는 DXMT 본가와 Mullion 최신판에 그대로 있어요(2026-11-27 확인). 표의 "—"는 그 고침이 없다는 뜻이고, 다른 방식으로 메모리를 관리할 수는 있어요.

## 다운로드

**[⬇︎ Miro.zip](https://github.com/boartat/Miro/releases/latest/download/Miro.zip)** · [모든 릴리즈](https://github.com/boartat/Miro/releases) · Apple 실리콘 Mac, macOS 14 이상

처음 열 때 경고가 뜨면 **시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기**를 눌러요. 안 되는 게임은 [이슈](https://github.com/boartat/Miro/issues/new/choose)로 알려 주세요.

## 출처와 라이선스

[Whisky](https://github.com/Whisky-App/Whisky)를 포크한 **GPL-3.0 이상** 프로젝트예요. [Wine](https://www.winehq.org), [DXMT](https://github.com/3Shain/dxmt), [Mullion](https://github.com/dttdrv/mullion), [DXVK](https://github.com/doitsujin/dxvk), [FEX](https://github.com/FEX-Emu/FEX), [Hadron](https://github.com/Broyojo/hadron), [Highball](https://github.com/gauthierpiarrette/highball), [MoltenVK](https://github.com/KhronosGroup/MoltenVK), [Gcenx의 빌드](https://github.com/Gcenx/macOS_Wine_builds), [winetricks](https://github.com/Winetricks/winetricks), Apple Game Porting Toolkit 위에 만들었어요. 전체 목록: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Apple D3DMetal 때문에 **무료로만** 배포해요. Apple, Microsoft, CodeWeavers, WineHQ, Valve, Whisky 프로젝트와 관계가 없어요.

<details>
<summary><b>만든 사람의 말</b></summary>

Mac에서 Windows 게임·프로그램을 실행하는 무료 오픈소스 런처인 Miro 입니다. [Whisky](https://github.com/Whisky-App/Whisky)(GPL-3.0)를 포크해서 만들었습니다..

참고: 이 프로젝트는 생성형 ai인 claude를 활용하여 제작하였으며, 해당 프로그램은 수익을 창출하지 않습니다. 또한 유료화 계획도 없으며 순전히 개인의 호기심에서 시작한 프로젝트입니다.
그냥 제가 쓰기 편하라고 만든 앱이다 보니 어느정도 유지보수는 진행할거지만 어디까지 된다는 보장못합니다. 따라서 사용자분들의 보고가 큰 도움이 될겁니다.
현재 ai티가 많이 날텐데, 초기버전이라 디자인적으로 신경을 많이 못썼습니다...ㅠ 새로운 엔진 도입하면서 갈아엎어보도록 하겠습니다.

기존의 와인기반 윈도우 호환 프로그램들은 너무 복잡했습니다. 게임하나 실행하는데 정말 미로같았거든요. 그래서 직관적으로 잘 작동하는 프로그램이 없을까 싶어서 미로를 계획 하게 되었습니다.
레티나 디스플레이 모드로 진행시 노치부분까지 게임을 꽉 채워주는 기능도 존재합니다. 
기존에 윈도우 pc를 쓰다가 맥으로 넘어오게 되었는데 저는 좀 쯔꾸르나 유니티게임같은것들 많이 즐기는편이라.. 이거 못하는게 좀 컸거든요.
그런데 과장 조금 보태서 미로를 쓰면서 큰 걱정이 없어졌습니다. 게임뿐만 아니라 프로그램들도 실행할 수 있으니 편하고요.
exe만 넘기는게 아니라, 게임 폴더 째로 미로에 던져넣으면 자동으로 인식하는 기능도 있답니다.

어쨌든 여러분들도 저와 같은 경험을 해보셨으면 하네요. 사족이 너무 길었네요. 감사합니다.

</details>

문의: [이슈](https://github.com/boartat/Miro/issues) · [minjae@ovqo.dev](mailto:minjae@ovqo.dev)

## English

**Miro** is a free launcher for Windows games and apps on Apple Silicon Macs. **miroe**, its next engine, is ARM64-native Wine + FEX with open-source Direct3D 12 ([Mullion](https://github.com/dttdrv/mullion)), researched together with [Claude](https://claude.ai) (AI); code and measurements are public.

Results (test programs on an M4 Pro, macOS 27; real games may differ): graphics memory left after discard bursts **−67%** (dynamic textures **−80%**, game-like test **−48 to −59%**) with no speed cost; 32-bit programs under Rosetta **57×** more frames; Direct3D 12 at feature level **12_2** / shader model **6.7** without D3DMetal; CJK text failures **−94%**. Details: [RESEARCH.md](RESEARCH.md). Credits: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
