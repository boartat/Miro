<div align="center">

# Miro ✦

**Windows 게임과 프로그램을, 호환성 걱정 없이 Mac에서.**

Apple 실리콘 Mac용 무료 오픈소스 Windows 게임·프로그램 런처, 그리고 애플 실리콘 전용 차세대 엔진 **miroe**

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/boartat/Miro)](https://github.com/boartat/Miro/releases/latest)
![Apple Silicon · macOS 14+](https://img.shields.io/badge/Apple%20Silicon-macOS%2014%2B-lightgrey)
![miroe: ARM64 Wine + FEX + Mullion](https://img.shields.io/badge/miroe-ARM64%20Wine%20%C2%B7%20FEX%20%C2%B7%20Mullion-8a2be2)

**[⬇︎ 다운로드](#다운로드)** · [성과](#성과) · [miroe](#miroe-차세대-엔진) · [출처와 라이선스](#출처와-라이선스) · [English](#english)

</div>

## 성과

Mac용 Wine에 남아 있던 병목을 직접 재고, 고치고, 다시 쟀어요.

| 문제 | 결과 |
| --- | --- |
| **동적 리소스 메모리가 돌아오지 않음** ([DXMT #260](https://github.com/3Shain/dxmt/issues/260)) | 몰아치기 뒤 GPU 메모리 **920 → 308MB (−67%)**, 동적 텍스처 **968 → 196MB (−80%)**. 게임형 테스트에서 교전 뒤 GPU 메모리 **−48~59%**. 속도 손해 없음 (MUMA) |
| **32비트 게임이 슬라이드쇼가 됨** ([DXMT #161](https://github.com/3Shain/dxmt/issues/161), Intel Wine + Rosetta) | 원인을 찾아 고쳐서 같은 시간에 **35 → 1,997프레임 (57배)**. `NX_COMPAT`가 있는 정상 경우와 같은 속도 |
| **D3DMetal 없이 DirectX 12** | ARM64 네이티브 Wine + FEX 위에서 [Mullion](https://github.com/dttdrv/mullion)으로 **D3D12 기능 수준 12_2, 셰이더 모델 6.7**. SM 5.0과 SM 6.0~6.6(웨이브 연산, 16비트, 디스크립터 힙 직접 접근) 셰이더 결과 모두 정확 |
| **한중일 글자가 네모로 나옴** | 다운로드 없이 Mac 글꼴을 연결해서 실패 **140 → 8개** (152개 중) |
| **Rosetta에서 시간이 어디에 쓰이나** | Wine 자체는 **1% 미만**, Rosetta가 번역한 Metal·GPU 드라이버가 **46~53%**. 그래서 ARM64 네이티브 엔진으로 가요 |
| **그래픽 효율** (Miro 1.1+) | 같은 장면에서 DXMT가 DXVK보다 **GPU를 약 3분의 1만** 써요 |

> 숫자는 M4 Pro, macOS 27에서 직접 만든 중립 테스트 프로그램으로 잰 거예요(실제 게임 성능과 다를 수 있어요). 방법과 원자료는 [`Engine/miroe`](Engine/miroe)에 모두 공개돼 있어요.

## Miro

![Miro 홈 화면](docs/screenshots/01-home.png)

- **끌어다 놓으면 끝**: 게임 폴더를 놓으면 등록되고, 플레이를 누르면 실행돼요.
- **엔진·그래픽 자동 선택**: 게임이 쓰는 DirectX 버전에 맞는 방식(DXMT · D3DMetal · DXVK)으로 실행하고, 안 되면 다음 방식으로 넘어가고, 잘 된 방식을 기억해요.
- **빠진 DLL 자동 설치**: 검증한 공식 재배포 패키지만, 해시를 확인해서 설치해요. 설치 전에 C: 드라이브 복구 지점을 만들어요.
- **게임별 설정**: 효율·기본·성능 모드, 노치까지 채우는 전체 화면, Retina, FPS 표시

## 다운로드

**[⬇︎ Miro 최신 버전 받기 (Miro.zip)](https://github.com/boartat/Miro/releases/latest/download/Miro.zip)** · [모든 릴리즈](https://github.com/boartat/Miro/releases)

- Apple 실리콘 Mac(M1 이후), macOS 14 이상. 첫 실행 때 호환 레이어(약 230MB)를 원래 배포처에서 받아요.
- `Miro.app`을 응용 프로그램 폴더로 옮겨요. 처음 열 때 경고가 뜨면 **시스템 설정 → 개인정보 보호 및 보안**에서 **그래도 열기**를 눌러요(애플 공증을 받지 않은 개인 프로젝트예요).
- 안 되는 게임은 [이슈](https://github.com/boartat/Miro/issues/new/choose)로 알려 주세요. 실행 로그(⌘L)를 붙여 주면 큰 도움이 돼요.

## miroe (차세대 엔진)

**애플 실리콘 전용 ARM64 네이티브 Wine + FEX 엔진**이에요. 여러 플랫폼을 두루 지원하는 대신 애플 실리콘 하나만 지원하고, 그만큼 병목을 없애는 데 집중해요.

- 기반: 최신 upstream Wine(ARM64 macOS 지원), [FEX](https://github.com/FEX-Emu/FEX), 그래픽은 [Mullion](https://github.com/dttdrv/mullion)(D3D10/11/12)
- 위 성과의 패치는 모두 [`Engine/miroe/patches`](Engine/miroe/patches)에 있어요.
- 연구 단계라서 아직 Miro 앱에는 들어가 있지 않아요. 계획과 문제 목록: [`BASE.md`](Engine/miroe/BASE.md), [`PROBLEMS.md`](Engine/miroe/PROBLEMS.md), [`RESEARCH.md`](Engine/miroe/RESEARCH.md)

## 출처와 라이선스

Miro는 [Whisky](https://github.com/Whisky-App/Whisky)를 포크해서 만들었고 **GPL-3.0 이상**이에요([`LICENSE`](LICENSE)). miroe의 패치는 각 부품과 같은 LGPL-2.1 이상이에요.

[Wine](https://www.winehq.org), [DXMT](https://github.com/3Shain/dxmt), [Mullion](https://github.com/dttdrv/mullion), [DXVK](https://github.com/doitsujin/dxvk) · [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS), [FEX](https://github.com/FEX-Emu/FEX), [Hadron](https://github.com/Broyojo/hadron), [Highball](https://github.com/gauthierpiarrette/highball), [MoltenVK](https://github.com/KhronosGroup/MoltenVK), [Gcenx의 macOS 빌드](https://github.com/Gcenx/macOS_Wine_builds), [winetricks](https://github.com/Winetricks/winetricks), Apple [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) 위에 만들었어요. 구성 요소별 라이선스와 가져온 것은 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)에 모두 적어 뒀어요. Apple D3DMetal은 비상업적 배포만 허용돼서 Miro는 **무료로만** 배포하고, 애플 파일은 고치거나 함께 배포하지 않아요.

Miro는 Apple, Microsoft, CodeWeavers, WineHQ, Valve, Whisky 프로젝트와 관계가 없어요.

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

<details>
<summary><b>빌드</b></summary>

Xcode 16 이상, Apple 실리콘 Mac.

```bash
xcodebuild -project Miro.xcodeproj -scheme Miro -configuration Release -derivedDataPath build build
```

miroe의 실습실 빌드 스크립트는 [`Engine/miroe/scripts`](Engine/miroe/scripts), 화면 없는 테스트는 [`Engine/tests`](Engine/tests)에 있어요.
</details>

## 문의

- 버그·호환성 보고: [이슈](https://github.com/boartat/Miro/issues/new/choose)
- 그 밖의 문의: [minjae@ovqo.dev](mailto:minjae@ovqo.dev)

## English

**Miro** is a free, open-source (GPL-3.0) launcher for Windows games and programs on Apple Silicon Macs, and **miroe** is its next engine: ARM64-native Wine + FEX, Apple silicon only, with [Mullion](https://github.com/dttdrv/mullion) for Direct3D 10/11/12.

**Results** (neutral test programs on an M4 Pro, macOS 27; real games may differ; methods and data in [`Engine/miroe`](Engine/miroe)):
- Dynamic-resource memory after a burst ([DXMT #260](https://github.com/3Shain/dxmt/issues/260)): **920 → 308 MB** (dynamic textures 968 → 196 MB), GPU memory after fights in a game-like test **−48 to −59%**, no speed cost.
- 32-bit programs without `NX_COMPAT` under Rosetta ([DXMT #161](https://github.com/3Shain/dxmt/issues/161)): **35 → 1,997 frames** in the same time, by giving pages execute permission only when code runs.
- Direct3D 12 at **feature level 12_2 without D3DMetal** on ARM64 Wine + FEX; shader model 6.7; SM 5.0 and SM 6.0-6.6 shaders (waves, 16-bit types, descriptor heap indexing) give exact results.
- CJK text without downloading fonts: failures **140 → 8** of 152.

Built on Whisky, Wine, DXMT, Mullion, DXVK, FEX, Hadron, Highball, MoltenVK, Gcenx's builds, winetricks and Apple's Game Porting Toolkit; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Contact: [issues](https://github.com/boartat/Miro/issues) or [minjae@ovqo.dev](mailto:minjae@ovqo.dev).
