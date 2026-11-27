# miroe: Mac용 Wine의 알려진 문제와 miroe의 방향

miroe는 Miro의 차세대 엔진이에요. **애플 실리콘 Mac 전용**으로, Wine 개발자와 Mac Wine 프로젝트들이 이미 알고 있는 문제를 모아서 그 약한 부분을 Mac 고유 기술로 보완하는 게 목표예요.

측정 결과와 첫 개선은 [README.md](README.md)에 있어요. 이 문서는 2026-11-26에 모은 자료예요.
- [Wine 버그 트래커](https://bugs.winehq.org)에서 운영체제가 macOS인 열린 버그 전부(604건)
- Mac Wine 프로젝트의 이슈: [Highball](https://github.com/gauthierpiarrette/highball/issues), [Gcenx macOS 빌드](https://github.com/Gcenx/macOS_Wine_builds/issues)
- Wine 개발자 논의: [MR 11058](https://gitlab.winehq.org/wine/wine/-/merge_requests/11058), [MR 11257](https://gitlab.winehq.org/wine/wine/-/merge_requests/11257), [DXMT PR 166](https://github.com/3Shain/dxmt/pull/166)

## 한눈에 보기

Wine 버그 트래커의 macOS 열린 버그 604건을 제목으로 나눴어요(대략적인 분류예요).

| 분야 | 건수 |
| --- | ---: |
| 특정 앱·게임의 충돌 (원인 미분류) | 288 |
| 그래픽 (D3D, OpenGL, Vulkan) | 66 |
| 입력 (마우스, 키보드, 컨트롤러, IME) | 53 |
| wineserver·ntdll·스레드·동기화 | 51 |
| .NET·설치 프로그램 | 44 |
| 글꼴·문자 (한중일 포함) | 21 |
| 오디오 | 19 |
| 다른 프로세스의 자식 창·런처 (CEF) | 16 |
| 동영상·코덱 | 14 |
| 전체 화면·창 순서·해상도·Retina | 11 |
| ARM64·16K 페이지·Rosetta | 11 |
| 네트워크 | 10 |

## 선행 기술 조사와 미해결 문제 (2026-11-27)

miroe는 이미 있는 기술을 다시 만들지 않아요. 아래는 공개된 성과를 모아 **채택할 것**, **고칠 것**, **직접 연구할 것**을 나눈 결과예요.

**조사 범위 (2026-11-27)**: 아래 프로젝트의 열린 이슈 목록, DXMT의 2026-07 이후 커밋 전부, Mullion의 커밋 전부(키워드 검색), Wine GitLab의 macOS 관련 MR, FEX의 macOS·ARM64EC·TSO 이슈, 우선 이슈 8개의 본문과 댓글을 읽었어요. 닫힌 이슈와 PR은 이 문제들과 관련된 것만 확인했어요. 모든 프로젝트의 닫힌 이슈 전부를 읽은 것은 아니에요.

### 상태 기준

| 상태 | 뜻 | miroe가 하는 일 |
| --- | --- | --- |
| **A** | 기존 프로젝트에서 해결됐고 채택할 수 있음 | 라이선스 확인 후 가져와요 |
| **B** | 해결책은 있지만 불안정하거나 불완전함 | 무엇이 모자란지 분석하고 개선해요 |
| **C** | 문제와 원인은 알려졌지만 구현된 해결책이 없음 | **직접 연구 대상** |
| **D** | 현상만 알려졌고 원인도 해결책도 없음 | **직접 연구 대상** (원인 찾기부터) |
| **E** | Apple의 권한, 비공개 API, 닫힌 기술에 막힘 | 할 수 있는 범위만 해요 |

### 조사한 프로젝트

| 프로젝트 | 라이선스 | 2026-11 상태 | miroe와의 관계 |
| --- | --- | --- | --- |
| [Wine](https://gitlab.winehq.org/wine/wine) | LGPL-2.1+ | **!12716 "Add support for ARM64 on macOS" 2026-11-26 병합.** macOS 27과 제한된 권한(개발자 계정)이 필요해요. !12349(mach port, 공유 리소스·프로세스 간 그래픽 준비), !12566(GCMouse 원시 입력), !11058(Metal 레이어 ExtEscape)은 열려 있어요 | 기반. 공식 ARM64 macOS 지원이 생겼으니 Hadron 패치 중 필요 없어진 것을 정리해야 해요 |
| [Wine Staging](https://gitlab.winehq.org/wine/wine-staging) | LGPL-2.1+ | Mac 전용 항목은 이번 조사에서 따로 찾지 못했어요 | Gcenx·Highball 빌드의 재료 |
| [CodeWeavers 공개 소스](https://media.codeweavers.com/pub/crossover/source/) | LGPL-2.1+ (Wine 부분) | CrossOver 26.3 트리(msync, Vulkan 자식 창의 CALayerHost 경로). 오늘은 목록 페이지를 받지 못해 새 버전은 확인하지 못했어요 | Miro 1.2의 최신 엔진 |
| [DXMT](https://github.com/3Shain/dxmt) | LGPL-2.1+ | 활발. 2026-07부터 **D3D12와 DXIL 변환**을 넣는 중. AI가 만든 PR은 받지 않아요 | MUMA의 기반 |
| [Mullion](https://github.com/dttdrv/mullion) | LGPL-2.1+ | **DXMT 포크, 매우 활발(커밋 1,355개).** D3D12 기능 수준 12_2, SM 6.7, DXR. Wukong 벤치마크에서 D3DMetal보다 빠르다고 보고해요. AI로 쓴 변경도 사람이 검토하면 받아요 | **D3D10/11/12 채택 1순위 후보.** #204, NV12, 메모리 한도 등이 이미 들어 있어요 |
| [DXVK](https://github.com/doitsujin/dxvk) / [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | zlib | 활발 / 3.1.1-macos 계열 | MUMA v2 메모리 정책의 참고 |
| [FEX-Emu](https://github.com/FEX-Emu/FEX) | MIT | FEX-2611.1. ARM64EC·WOW64 이슈 다수 열림 | Intel 코드 번역 |
| [Hadron](https://github.com/Broyojo/hadron) | BSD(자체) + 각 부품 | 활발. Wine 패치 57개, FEX 7개, Mesa(KosmicKrisp) 41개, vkd3d-proton 4개, mtld3d 3개. `docs/findings.md`에 해결 기록 60여 개 | 지금 엔진의 기반 |
| [MetalSharp-Wine](https://github.com/metalsharp/MetalSharp-Wine) | 자체 AGPL-3.0, Wine 변경 LGPL | ARM64 Wine 11.20 + FEX. 기본 D3D 경로가 Mullion이에요. **msync를 ARM64에서 기본으로 켜고, FEX TSO 에뮬레이션도 켜요**(c9563827) | LGPL인 Wine 변경만 가져올 수 있어요 |
| [VKD3D-Proton](https://github.com/HansKristian-Work/vkd3d-proton) | LGPL-2.1 | Mac용은 Hadron 패치(KosmicKrisp 위), [MetalVulkan](https://github.com/metalsharp/MetalVulkan)(AGPL, **제외**) | D3D12의 두 번째 경로 |
| [KosmicKrisp](https://docs.mesa3d.org/drivers/kosmickrisp/) | MIT (Mesa) | Metal 4 위의 Vulkan. [Metal 결함 목록](https://docs.mesa3d.org/drivers/kosmickrisp/workarounds.html)을 날짜별로 관리해요 | Vulkan 경로, Apple 결함 자료 |
| [MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Apache-2.0 | 열린 이슈 405개. DXVK-macOS의 기반 | 참고 |
| [mtld3d](https://github.com/athei/mtld3d) | zlib | D3D9(Ex) → Metal, 활발 | D3D9 채택 후보 (Hadron이 이미 씀) |
| [WineMetalGL](https://github.com/metalsharp/WineMetalGL) | LGPL-3.0 | OpenGL 4.6 → Metal, ARM64 Wine 지원(3.7.0부터) | OpenGL 채택 후보 |
| [Hangover](https://github.com/AndreRH/hangover) | LGPL-2.1 | ARM64 **Linux**용. ARM64EC 방식은 Wine 본체로 들어갔어요 | Mac 대상이 아니라 참고만 |
| [Neutron](https://github.com/codeWonderland/neutron) | MIT | 2026-10 이후 멈춤. `d3dprobe`(재현 도구), DXMT·winemac 패치 | 재현 도구와 패치 참고 |
| [WineForge](https://github.com/Alien4042x/WineForge) | LGPL-2.1+ (Wine 변경) | Wine 11.12+, USync 6 | 동기화 참고 |
| [Highball engine](https://github.com/gauthierpiarrette/highball-engine) | LGPL-2.1 | Wine 패치 35개 + ARM64 패치 | NX, 자식 창, 4K 페이지 패치 |
| [Apple Metal 문서](https://developer.apple.com/documentation/metal) | — | placement sparse 리소스(macOS 26.4+), residency set, `setPurgeableState`, `recommendedMaxWorkingSetSize`. 하드웨어 TSO를 켜는 공개 API는 없어요 | 기준 문서 |

### 우선 이슈 교차 확인

"열려 있다"만으로 미해결이라고 보지 않고, 포크와 커밋을 다 확인했어요.

| 이슈 | 원래 상태 | 교차 확인 결과 | 분류 |
| --- | --- | --- | --- |
| [DXMT #204](https://github.com/3Shain/dxmt/issues/204) 상수 버퍼 `UpdateSubresource`가 제곱으로 느려짐 | 열림, 댓글 0 | DXMT main(faa73e4)은 그대로예요. **Mullion f1be9e6e(2026-10-11)가 제보자의 제안대로 고쳤어요.** 다만 드라이버 비용이 왜 제곱으로 느는지, 왜 픽셀 셰이더에만 생기는지는 아무도 설명하지 못했어요 | **B** (증상은 해결, 원인은 C) |
| [DXMT #161](https://github.com/3Shain/dxmt/issues/161) WoW64의 placed 버퍼가 Tahoe에서 매우 느림 | 열림 | DXMT·Mullion 모두 `aligned_malloc` 그대로예요. 우회책만 있어요: exe에 `NX_COMPAT` 표시, Gcenx의 `WINE_NX_COMPAT`(빌드 삭제됨), Highball 0013(Rosetta에서 DEP를 항상 켬, 프로세스 전체 정책을 바꿈). 3Shain이 말한 올바른 해결("DEP 정책은 그대로 두고 DXMT의 placed 메모리만 실행 불가로")은 구현된 곳이 없어요 | **C** |
| [DXMT #246](https://github.com/3Shain/dxmt/issues/246) 3D 텍스처 UAV의 `FirstWSlice` ≠ 0 | 열림, "지원 안 함" | Mullion은 생성은 받아 주지만(dcddabe) 뷰가 깊이 전체를 덮어서, 셰이더의 w 좌표에 `FirstWSlice`가 더해지지 않아요 | **B** |
| [DXMT #230](https://github.com/3Shain/dxmt/issues/230) UE5 타임스탬프 쿼리 | 열림 | DXMT #251로 고쳐졌어요(3Shain이 확인 요청). Neutron에도 패치가 있어요 | **A** |
| [DXMT #229](https://github.com/3Shain/dxmt/issues/229) NV12(Media Foundation 동영상), 데스크톱 창 swapchain | 열림 | Mullion ecfa2153이 NV12와 다른 planar 형식을 넣었어요. DXMT는 PR을 요청한 상태예요 | **A** (Mullion) |
| [DXMT #265](https://github.com/3Shain/dxmt/issues/265) 시작할 때 가끔 충돌 | 닫힘 | fb451568에서 고쳐졌고 제보자가 20번 연속 실행으로 확인했어요 | **A** |
| [DXMT #266](https://github.com/3Shain/dxmt/issues/266) Skyrim 톤맵 NaN | 열림, 댓글 0 | 제보자는 DXBC의 min/max/saturate가 `air.fast_*`로 바뀌는 것을 의심해요. Mullion은 DXIL 경로만 NaN을 고쳤고(db92b2e), DXBC 경로의 `FastVariant = true` 기본값은 그대로예요 | **C** |
| [Wine #60263](https://bugs.winehq.org/show_bug.cgi?id=60263) 다른 프로세스의 자식 창 Metal swapchain (Steam이 까맘) | UNCONFIRMED | 참고 구현이 여럿 있어요: 버그 첨부(82030), Neutron `winemac-remote-metal.patch`, Highball 0007·0031. Wine 공식 방향은 rbernon의 mach port 교환(!12349) 위에 프로세스 간 렌더링을 올리는 것이에요 | **B** (공식 방향 추적) |
| [DXMT #260](https://github.com/3Shain/dxmt/issues/260) 동적 리소스 메모리 | 열림 | **MUMA v2(우리)**. Mullion은 작업 세트 95% 한도와 메모리 압력에 따른 예산(eea1089)을 넣었지만, 예비 블록 회수와 purgeable은 없어요 | **B** (우리 결과 보존, 남은 검증) |

### 분야별 문제

형식: **상태 · 영향 · 난이도 · 우선순위**. 난이도 상(몇 달 이상) / 중(몇 주) / 하(며칠). 우선순위 1이 가장 높아요.

#### Flux: 그래픽 명령 처리
- **F1. DEFAULT 상수 버퍼 갱신이 제곱으로 느려짐** ([DXMT #204](https://github.com/3Shain/dxmt/issues/204)) · B · 그리기마다 상수 버퍼를 갱신하는 D3D11 게임(제보자는 CS2) · 하(채택) / 중(원인) · **2**
  - 소스: `src/d3d11/d3d11_buffer.cpp`(`DynamicBuffer`가 버퍼의 플래그를 물려받음), `src/dxmt/dxmt_buffer.cpp`(페이지 나눠 쓰기)
  - 선행 구현: Mullion [f1be9e6e](https://github.com/dttdrv/mullion/commit/f1be9e6e), [88a5ba3](https://github.com/dttdrv/mullion/commit/88a5ba3)(rename이 실제로 묶인 슬롯만 다시 인코딩)
  - 남은 것: `ExecuteCommandList`의 나눠 쓰기 위치 복원(제보자가 경고), 2048~4096바이트의 낭비 구간, 서로 다른 `MTLBuffer` 수에 대해 드라이버 비용이 제곱으로 느는 이유. MUMA의 예비 블록 회수와 같은 코드(`DynamicBuffer`)를 지나요
  - 재현: 제보자의 `cbuffer_cost.exe`, `Engine/tests/c/d3d11-game-test.c`에 DEFAULT 상수 버퍼 모드를 더하면 돼요
- **F2. Horizon 5의 PSO 생성 실패 3,700번(블렌딩 + MSAA 8x)** ([Mullion #34](https://github.com/dttdrv/mullion/issues/34)) · D · 끊김 · 중 · 4

#### MetalLink: x86 / ARM64EC / ARM64 경계
- **L1. 하드웨어 TSO** · E → 이제 풀 수 있음 · FEX로 번역하는 모든 게임의 속도 · 하 · **3** (개발자 계정 승인 뒤)
  - Hadron FEX 패치 0004가 `thread_set_x86_64_compat`로 스레드마다 하드웨어 TSO를 켜요. 제한된 권한 `com.apple.developer.cross-architecture-support`가 필요해요. MetalSharp는 권한 없이 FEX의 소프트웨어 TSO를 기본으로 켜요(RDR2의 작업 대기열 때문에)
- **L2. FEX ARM64EC 문제들** · B/C · FEX 쪽에서 활발히 고치고 있어요: [#6107](https://github.com/FEX-Emu/FEX/issues/6107)(바뀌지 않은 코드에 VirtualProtect를 해도 코드를 버려서 끊김), [#6015](https://github.com/FEX-Emu/FEX/issues/6015), [#6023](https://github.com/FEX-Emu/FEX/issues/6023), [#6073](https://github.com/FEX-Emu/FEX/issues/6073) · 추적만 · 5

#### ShaderVault: 셰이더 컴파일
- **S1. Metal 컴파일러가 아주 큰 compute 셰이더에서 죽음** ([Hadron #61](https://github.com/Broyojo/hadron/issues/61), Subnautica 2) · D · Nanite를 쓰는 UE5 게임 전부(Vulkan 경로) · 상 · 4
  - vkd3d-proton → KosmicKrisp가 셰이더 하나에 8~13MB의 MSL을 만들어요. Mullion은 MSL이 아니라 AIR를 바로 만들어서 이 경로를 피할 수 있는지 확인해야 해요
- **S2. D3D12 시작에 셰이더 컴파일 10분** ([Hadron #84](https://github.com/Broyojo/hadron/issues/84), Ready or Not) · D · 중 · 4
- **S3. 비동기 컴파일과 캐시** · A (Mullion) · 컴파일 스레드(6625e0d, cf82aa9), 기다리지 않는 셰이더 캐시(ee1af15), binary archive(52a104a) · 하(채택) · 3

#### OpenDX12: 공개 D3D12 변환
- **D1. D3D12 기반 선택** · A · Mullion(Metal 직접, FL 12_2)과 vkd3d-proton + KosmicKrisp(Hadron) 두 길이 있어요. DXMT 본가도 D3D12를 넣는 중이에요 · 하 · **2** (채택 결정)
- **D2. 남은 게임 문제** · B: [Mullion #239](https://github.com/dttdrv/mullion/issues/239)(DXR compute에서 GPU 한계), [#258](https://github.com/dttdrv/mullion/issues/258)(Wukong 선 무늬), [#204](https://github.com/dttdrv/mullion/issues/204)(Spider-Man 2 placed 3D 텍스처) · 추적 · 5

#### Native Surface: 창과 Swapchain
- **N1. 다른 프로세스의 자식 창** ([Wine #60263](https://bugs.winehq.org/show_bug.cgi?id=60263), [DXMT #141](https://github.com/3Shain/dxmt/issues/141), [#183](https://github.com/3Shain/dxmt/issues/183)) · B · Steam, Electron·CEF 런처 · 중 · 3
  - Wine 공식 방향(!12349 → 프로세스 간 렌더링)이 움직이고 있어서, 그 전까지는 참고 구현을 채택하고 공식이 나오면 갈아타요
- **N2. ProMotion V-Sync** ([DXMT #26](https://github.com/3Shain/dxmt/issues/26)) · A/B · Hadron DXMT 패치 0001(Windows처럼 디스플레이 동기화로 Present) · 하 · 4

#### Native Media: 동영상
- **M1. NV12 텍스처** ([DXMT #229](https://github.com/3Shain/dxmt/issues/229)) · A · Mullion ecfa2153 · 하 · 3
- **M2. VideoToolbox로 해독한 프레임을 복사 없이 D3D11 텍스처로** · C · 지금은 GStreamer(소프트웨어) → CPU 메모리 → GPU 업로드예요. 구현된 곳을 찾지 못했어요 · 상 · 4

#### WoW64: 32비트
- **W1. 32비트 게임의 DEP와 Metal placed 메모리** ([DXMT #161](https://github.com/3Shain/dxmt/issues/161)) · **C → miroe 해결 후보 (2026-11-27, [RESEARCH.md](RESEARCH.md) W1)** · `NX_COMPAT`가 없는 32비트 D3D10/11 게임 전부(옛 Unity, 비주얼 노벨, GOG 고전). DXMT와 DXVK 모두, Rosetta와 FEX 모두 · 중 · **1 (선정)**
  - 원인(알려짐): DEP가 꺼진 프로세스에서 Wine은 `force_exec_prot`로 모든 읽기 가능한 페이지에 `PROT_EXEC`를 붙여요. Tahoe의 Metal은 실행 가능한 placed 메모리를 몹시 싫어하고, Rosetta에서는 쓰기+실행 페이지를 처음 만질 때마다 Mach 왕복이 생겨요([athei/wine-build#3](https://github.com/athei/wine-build/issues/3): 190배). 따로, placed 버퍼가 가상 메모리 한 영역에 있지 않아서 프레임 캡처가 죽어요
  - 소스: DXMT `src/dxmt/dxmt_buffer.cpp`(`CpuPlaced` → `wsi::aligned_malloc`), Wine `dlls/ntdll/unix/virtual.c`(`force_exec_prot`), `loader.c`(NX 판단)
  - 우회책(B): exe 표시 바꾸기, Highball 0013(DEP를 항상 켬, 프로세스 전체에 영향)
  - 재현: `NX_COMPAT` 없이 링크한 32비트 D3D11 테스트로 Present 횟수와 인코드 스레드 시간을 재요
  - **2026-11-27 결과**: 원인을 Wine 없이 분리했어요. Rosetta에서 쓰기+실행 메모리 위의 Metal no-copy 버퍼는 GPU가 쓴 뒤 다음 CPU 접근이 약 1.2초 멈춰요. Wine의 지연 실행 권한 패치(`patches/wine-x86_64/0001`)로 `NX_COMPAT` 없는 32비트 테스트가 35 → 1,997프레임(`NX_COMPAT` 있을 때와 같음)이 됐고, DEP가 꺼진 코드 실행 9가지는 그대로 동작해요
- **W2. FEX WOW64의 DEP 꺼짐 문제** ([FEX #6135](https://github.com/FEX-Emu/FEX/issues/6135), [#5907](https://github.com/FEX-Emu/FEX/issues/5907)) · B/C · W1과 같은 뿌리 · 추적 · 3
- **W3. 4GB 아래 메모리와 16K 페이지** · E → 풀 수 있음 · Wine !12716과 Hadron 모두 제한된 권한이 필요해요. Highball은 `posix_spawnattr_set_4k_page_size_np`로 4K 페이지를 써요(ARM64 0024) · 중 · **3**

#### Trace: 차등 분석
- **T1. 자동 호환성 진단** · B/C · Mullion에는 분야별 추적(`MULLION_TRACE_*`), `mullion-diag`, 일부러 망가뜨린 패치로 테스트를 검증하는 방식(`tests/breaks`)이 있어요. 같은 실행 파일을 D3DMetal과 비교하는 방식은 #204 제보자가 손으로 했어요. **이걸 자동으로 하는 도구는 찾지 못했어요** · 중 · 4

#### Native Sync: 동기화
- **Y1. 모든 이벤트·세마포어가 wineserver 왕복** ([Hadron #148](https://github.com/Broyojo/hadron/issues/148)) · B · Unity 게임 스레드 시간의 55%(Arknights: Endfield, M4 Pro) · 중(채택) · **2**
  - 선행 구현: CrossOver msync(x86_64), **MetalSharp-Wine이 ARM64 Wine 11.20에서 msync를 기본으로 켬**(LGPL Wine 변경), WineForge USync 6, Highball 0014, 제보자의 공유 메모리 + `os_sync_wake_by_address` 시험 구현(55% → 1.7%)
  - 남은 것: 지금 기반(Hadron Wine 11.22)에는 없어요. `OS_SYNC_WAIT_ON_ADDRESS_SHARED`의 프로세스 간 동작은 문서에 없어요

#### Native Input: 입력
- **I1. GCMouse 원시 입력** · B · Wine !12566(mzent, 열림), !11799, !11999 · 하(채택) · 4
- **I2. 전체 화면에서 화면 아래 끝에 Mac 커서가 다시 나옴** ([Hadron #85](https://github.com/Broyojo/hadron/issues/85)) · D · 하 · 5

#### 메모리
- **R1. 동적 리소스의 예비 블록** ([DXMT #260](https://github.com/3Shain/dxmt/issues/260)) · B (MUMA v2) · 남은 것: 실제 메모리 압력 아래 purge, 텍스처 purgeable, Unity·Unreal 업로드 패턴 · 중 · 3
- **R2. 자기 프로세스의 `ReadProcessMemory`가 안 쓴 페이지를 모두 상주시킴** ([Hadron #151](https://github.com/Broyojo/hadron/issues/151)) · B (제보자의 `mincore` 시험 구현, 미병합) · 안티치트가 있는 게임의 메모리가 끝없이 늘어요 · 하 · 3

#### Nexus: 적응형 엔진 선택
- **X1. 게임별 엔진·그래픽 경로 선택** · B · Miro 1.2의 LaunchPlanner + highball-db(CC0), MetalSharp의 게임별 경로 · 중 · 4

#### E: Apple에 막힌 것
- **E1. 제한된 권한** `cross-architecture-support`: 4GB 아래 메모리와 하드웨어 TSO에 필요해요. 유료 개발자 계정으로 받을 수 있어요([Wine 위키](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-Building/ARM64-Provisioning-Profiles)). 사용자 계정은 2026-11-27 현재 처리 중이에요
- **E2. D3DMetal**: 닫힌 소스라 고칠 수 없어요. 비교 기준으로만 써요
- **E3. Metal 컴파일러·드라이버 결함**: KosmicKrisp의 KK_WORKAROUND 목록과 Mullion `docs/workarounds.md`가 날짜별로 관리해요. 우리는 재현이 되면 Apple Feedback으로만 알려요
- **E4. Rosetta 종료(macOS 28)**: 피할 수 없어요. ARM64 + FEX로 가는 이유예요

### 선정: W1 (32비트 DEP와 Metal placed 메모리)

아직 풀리지 않은 문제 중 파급력이 가장 큰 과제로 **W1**을 골랐어요.
- **영향이 넓어요.** `NX_COMPAT`가 없는 32비트 D3D10/11 게임 전부예요. DXMT와 DXVK 모두, Rosetta와 FEX 모두 해당해요. 증상은 "fps는 높은데 슬라이드쇼"라서 사용자가 원인을 알 수 없어요
- **원인은 알려졌는데 올바른 해결이 없어요(C).** 있는 것은 프로세스 전체의 DEP 정책을 바꾸는 우회뿐이고, 그건 DEP를 정말 꺼야 하는 옛 프로그램을 깰 수 있어요
- **지금 이 Mac에서 바로 잴 수 있어요.** Rosetta 경로(Intel용 Wine 11.21 + DXMT i386)는 개발자 계정 없이 돌아가요
- 다음 후보: **Y1**(동기화, 해결책이 있어 채택 작업), **F1**(Mullion에서 채택하고 원인 연구), **D1**(D3D12 기반 결정)

연구 방향: DEP 정책은 그대로 두고, (1) DXMT의 placed 메모리를 Wine을 거쳐 한 영역에 모아 할당하고, (2) 그 영역만 실행 불가로 둬요. 3Shain이 이슈에서 말한 올바른 해결이에요. 여기에 Wine 쪽에서 "DEP가 꺼져도 실제로 실행되는 페이지에만 실행 권한을 주는" 방식이 가능한지도 재 봐요.

## 문제 목록 (2026-11-26, 분야별 배경)

각 항목은 **문제 → 근거 → 지금 상황 → miroe의 방향** 순서예요. 난이도는 상(몇 달 이상), 중(몇 주), 하(며칠)예요.

### 1. CPU 번역: Rosetta가 끝나 가요 (난이도 상, 필수)

- **문제**: Windows 게임 코드는 Intel용이라 지금은 Rosetta 2가 번역해요. Apple은 macOS 27까지만 Rosetta를 온전히 지원하고, macOS 28(2027)부터는 일부 오래된 게임용으로만 남긴다고 했어요. Rosetta의 x87(옛 부동소수점) 처리도 느려요.
- **근거**: Wine on AArch64가 macOS에서 실행 안 됨 [#58567](https://bugs.winehq.org/show_bug.cgi?id=58567), 호스트 페이지 정렬 변경이 Rosetta에서 Wine을 깨뜨림 [#58084](https://bugs.winehq.org/show_bug.cgi?id=58084), x87 가속 프로젝트 [rosettax87](https://github.com/Lifeisawful/rosettax87)
- **지금 상황**: [MetalSharp Wine](https://github.com/metalsharp/MetalSharp-Wine)(ARM64/ARM64EC Wine + FEX), CrossOver ARM 빌드, Ferry, MacLauncher가 FEX로 가고 있어요.
- **miroe**: 엔진 자체는 ARM64로 네이티브 실행하고, 게임의 Intel 코드만 FEX로 번역해요. 전환기에는 Rosetta 경로를 예비로 둬요.
- **측정 (2026-11-27)**: 그리기 명령이 많은 D3D11 장면에서 CPU 시간의 46~53%가 Rosetta가 번역한 Metal·GPU 드라이버였고, Wine의 Unix 쪽은 1% 미만이었어요. ARM64 네이티브 실행이 가장 큰 개선 후보예요.

### 2. ARM64 Mac의 16K 메모리 페이지 (난이도 상)

- **문제**: Windows는 4K 단위로 메모리를 다루는데, 애플 실리콘 macOS는 16K 단위예요. ARM64로 직접 돌면 메모리 보호, 스택 가드 페이지, 정렬이 어긋나요.
- **근거**: 16K 페이지에서 4K 해제가 안 맞음 [#60572](https://bugs.winehq.org/show_bug.cgi?id=60572), 스레드 스택 가드 페이지 처리 [#60571](https://bugs.winehq.org/show_bug.cgi?id=60571), ARM64EC 64K 섹션 정렬 [#60570](https://bugs.winehq.org/show_bug.cgi?id=60570), ARM64EC 메모리 순서 [#60568](https://bugs.winehq.org/show_bug.cgi?id=60568) · [#60569](https://bugs.winehq.org/show_bug.cgi?id=60569), macOS에서 CPU 기능 조회가 비어 있음 [#60573](https://bugs.winehq.org/show_bug.cgi?id=60573), macOS에서 페이지 경계 접근 오류를 %gs 오류로 잘못 판단 [#60543](https://bugs.winehq.org/show_bug.cgi?id=60543)
- **지금 상황**: 버그는 열려 있고, 주로 ARM64 Wine을 만드는 사람들이 보고 중이에요.
- **miroe**: 4K 동작을 검증하는 화면 없는 테스트를 먼저 만들고, 고친 것은 Wine에도 돌려줘요.

### 3. 동기화와 wineserver 왕복 (난이도 중)

- **문제**: Windows의 잠금·이벤트를 Wine은 별도 프로세스(wineserver)를 거쳐 처리해요. Linux는 커널 기능(ntsync)으로 이 왕복을 줄이는데, macOS에는 그런 커널 기능이 없어요. 공식 Wine의 Mac 빌드에는 빠른 동기화가 없어요. Mach 세마포어를 쓰는 [msync](https://github.com/marzent/wine-msync)(LGPL-2.1, MR 11058을 쓴 mzent가 만들었어요)가 있지만, Highball 같은 CrossOver 계열 엔진에만 들어 있어요. 필요 없이 CPU를 계속 쓰는 대기 루프도 보고돼 있어요.
- **근거**: 스레드 풀 타이머가 할 일 없이 계속 돎 [#60694](https://bugs.winehq.org/show_bug.cgi?id=60694), CoreAudio 타이머 스레드가 바쁘게 기다림 [Gcenx #157](https://github.com/Gcenx/macOS_Wine_builds/issues/157)
- **miroe**: msync를 기본으로 넣어요(LGPL이라 가져다 쓸 수 있어요). 바쁜 대기 루프는 측정해서 없애요. 우리 벤치마크로 전후를 비교해요.

### 4. Metal 연결과 창 그리기 (난이도 중~상)

- **문제**: DXMT 같은 Metal 기반 그래픽이 Wine 창에 그리는 공식 통로가 없어요. Wine 창 구조가 바뀌면서 창 이동과 GDI 그리기 사이의 처리도 불안정해요.
- **근거**: `macdrv_surface_flush`와 `macdrv_WindowPosChanged`의 교착(언리얼 게임) [#60493](https://bugs.winehq.org/show_bug.cgi?id=60493), OpenGL 3.2+ 컨텍스트 생성 실패 [#60492](https://bugs.winehq.org/show_bug.cgi?id=60492), Unity 6이 D3D11 펜스에서 충돌 [#60300](https://bugs.winehq.org/show_bug.cgi?id=60300), DXGI 디스플레이 모드 목록이 일부만 구현됨 [#60222](https://bugs.winehq.org/show_bug.cgi?id=60222)
- **지금 상황**: Wine은 새 프로세스 간 GL 구조가 끝나면 winevulkan 안에 공식 Metal 통로를 만들 계획이에요(DXMT PR 166에서 mzent의 답).
- **miroe**: 그때까지는 Miro Metal Bridge를 써요. 공식 통로가 생기면 갈아타요. 교착(#60493) 같은 창 처리 버그는 다리와 같은 코드 근처라 우리 테스트로 재현해 볼 가치가 있어요.

### 5. 다른 프로세스의 자식 창: 런처가 까맣게 나와요 (난이도 상)

- **문제**: Steam, EA app 같은 런처는 웹 화면(CEF)을 다른 프로세스에서 그려서 창 안에 붙여요. Mac 드라이버는 이걸 제대로 못 보여 줘요.
- **근거**: 다른 프로세스 자식 창이 안 보임 [#35456](https://bugs.winehq.org/show_bug.cgi?id=35456), 프로세스 간 Metal 스왑체인 미구현(Steam이 까맣게 나옴) [#60263](https://bugs.winehq.org/show_bug.cgi?id=60263), GDI 자식 창이 OpenGL 창 뒤에 숨음 [#60578](https://bugs.winehq.org/show_bug.cgi?id=60578), EA app 화면이 하얗게 나옴 [#60282](https://bugs.winehq.org/show_bug.cgi?id=60282), [Gcenx #170](https://github.com/Gcenx/macOS_Wine_builds/issues/170)
- **지금 상황**: Wine 개발진의 합성(compositing) 개편이 이 문제를 겨냥하고 있어요.
- **miroe**: 직접 풀기보다 공식 개편을 따라가요. 그 사이에는 런처별 우회 설정(CEF 옵션)을 써요.

### 6. 전체 화면, 창 순서, 해상도, 게임 모드 (난이도 중)

- **문제**: macOS는 Windows처럼 해상도를 바꾸지 않아서 Wine이 흉내 내는데, 그 과정에서 화면이 확대되거나 창 순서가 틀어져요. Wine 프로세스는 앱 번들이 아니라서 macOS 게임 모드도 안 켜져요.
- **근거**: 전체 화면 창 위의 창이 뒤에 그려짐 [#60266](https://bugs.winehq.org/show_bug.cgi?id=60266), 해상도 흉내 모드에서 화면 일부가 확대됨 [#60736](https://bugs.winehq.org/show_bug.cgi?id=60736), 해상도가 바뀌면 Retina가 꺼짐 [#42973](https://bugs.winehq.org/show_bug.cgi?id=42973), DPI 비율 계산 중 중단 [#60798](https://bugs.winehq.org/show_bug.cgi?id=60798), Unity 게임이 앞으로 안 나옴 [#51194](https://bugs.winehq.org/show_bug.cgi?id=51194), 게임 모드 [Highball #338](https://github.com/gauthierpiarrette/highball/issues/338)
- **miroe**: Mac식 전체 화면(Space)과 해상도 흉내를 Metal 스케일링으로 처리하고, 게임 카테고리로 표시된 로더로 게임 모드를 켜요. Miro가 이미 가진 노치 전체 화면·Retina 설정을 엔진 안으로 옮겨요.

### 7. 입력: 컨트롤러 지연, 키, 커서 (난이도 하~중)

- **문제**: 컨트롤러 입력이 쌓이기만 하고 버려지지 않아 지연이 점점 커져요. 일부 키 조합과 커서 숨김도 어긋나요.
- **근거**: HID 입력 큐가 오래된 보고를 버리지 않아 컨트롤러 지연이 커짐 [#60522](https://bugs.winehq.org/show_bug.cgi?id=60522), 커서 숨김이 다음 메시지 때까지 늦어짐 [#60510](https://bugs.winehq.org/show_bug.cgi?id=60510), 오른쪽 Shift가 왼쪽으로 인식됨 [#44382](https://bugs.winehq.org/show_bug.cgi?id=44382), Ctrl+숫자가 숫자로 입력됨 [#53243](https://bugs.winehq.org/show_bug.cgi?id=53243), 제조사 전용 USB 장치 무시 [#60641](https://bugs.winehq.org/show_bug.cgi?id=60641)
- **miroe**: 컨트롤러는 Apple GameController 프레임워크로 직접 받아요. 입력 지연은 측정 도구를 만들어 숫자로 확인해요. 한국어·일본어 IME도 테스트 대상에 넣어요.

### 8. 오디오 (난이도 하~중)

- **문제**: CoreAudio 경로가 짧은 주기를 요청받으면 바쁘게 기다리면서 CPU를 써요. 마이크 문제도 있어요.
- **근거**: [Gcenx #157](https://github.com/Gcenx/macOS_Wine_builds/issues/157), [Highball #601](https://github.com/gauthierpiarrette/highball/issues/601)
- **miroe**: CoreAudio 저지연 경로를 측정해서 고쳐요. Highball 엔진의 오디오 보정 라이브러리(MIT)도 참고해요.

### 9. 동영상과 컷신 (난이도 중)

- **문제**: Windows 동영상 기능(Media Foundation)을 Wine은 GStreamer로 흉내 내요. 그래서 AAC 소리나 일부 형식에서 컷신이 깨져요. GStreamer를 따로 들고 다녀야 해서 크기도 커요.
- **근거**: Unity 게임 영상에서 AAC 오류 [#59414](https://bugs.winehq.org/show_bug.cgi?id=59414), MF 텍스처 플래그 [#59432](https://bugs.winehq.org/show_bug.cgi?id=59432), WMV2 영상 멈춤 [#60045](https://bugs.winehq.org/show_bug.cgi?id=60045)
- **miroe**: Mac에 이미 있는 하드웨어 디코더(VideoToolbox, AVFoundation)로 H.264·HEVC·AAC를 직접 풀어요. 더 빠르고 전력도 덜 쓰고, GStreamer가 필요 없는 형식이 늘어나요.

### 10. 글꼴과 한중일 문자 (난이도 하, Miro 사용자에게 중요)

- **문제**: macOS에서 GDI+가 한중일 문자를 네모(□)로 그려요. Windows 글꼴이 없으면 글자가 깨지거나 엉뚱한 글꼴로 나와요.
- **근거**: GDI+가 한중일 문자를 네모로 그림 [#60881](https://bugs.winehq.org/show_bug.cgi?id=60881), 벵골어 [#60181](https://bugs.winehq.org/show_bug.cgi?id=60181), 히브리어 [#44598](https://bugs.winehq.org/show_bug.cgi?id=44598)
- **miroe**: Windows 글꼴 이름(맑은 고딕, MS Gothic 등)을 macOS 시스템 글꼴로 자동 연결해요.
- **진행 (2026-11-27)**: `prefix/cjk-fonts.py`로 새 C: 드라이브의 실패가 152개 중 140개에서 8개(Segoe UI만)로 줄었어요. 다운로드는 없어요. 새로 찾은 문제: Wine의 GDI+가 Apple SD 산돌고딕 Neo, 히라기노 명조, Songti, Heiti를 찾지 못해요(GDI는 찾아요). 그래서 한국어는 지금 Arial Unicode MS에 연결해요. GDI+를 고치는 게 다음 일이에요.

### 11. 메모리 (난이도 중)

- **문제**: 애플 실리콘은 CPU와 GPU가 메모리를 같이 써요. 게임이 메모리 정보를 잘못 받으면 캐시를 너무 크게 잡아 스왑이 생기고 프레임이 떨어져요.
- **근거**: 메모리 사용량 보고가 macOS에서 틀림 [#60619](https://bugs.winehq.org/show_bug.cgi?id=60619) · [#60621](https://bugs.winehq.org/show_bug.cgi?id=60621), M4 Pro 24GB에서 RDR2가 메모리 증가와 스왑으로 느려짐 [Highball #398](https://github.com/gauthierpiarrette/highball/issues/398)
- **miroe**: 통합 메모리에 맞는 메모리·VRAM 값을 보고하고, 게임별 메모리 사용을 측정해요.

### 12. 네트워크 (난이도 하~중)

- **근거**: macOS 27.3에서 TCP 로컬 포트가 0으로 남음 [#60704](https://bugs.winehq.org/show_bug.cgi?id=60704), wineserver의 TCP 연결 나열 중 중단 [#60097](https://bugs.winehq.org/show_bug.cgi?id=60097), VPN 인터페이스가 있으면 런처가 멈춤 [#60432](https://bugs.winehq.org/show_bug.cgi?id=60432)
- **miroe**: 새 macOS 버전이 나오면 네트워크 테스트를 자동으로 돌려요.

### 13. 배포와 패키징 (난이도 하)

- **문제**: Homebrew의 Wine 패키지가 2026년 3분기부터 비활성화됐어요. Gcenx는 공식 WineHQ 패키지에 추가 패치를 넣지 말라는 요청을 받아서, 공식 빌드로는 DXMT 같은 기능을 쓸 수 없어요.
- **근거**: [#58946](https://bugs.winehq.org/show_bug.cgi?id=58946), [Gcenx #168](https://github.com/Gcenx/macOS_Wine_builds/issues/168), [DXMT #194의 Gcenx 답변](https://github.com/3Shain/dxmt/issues/194)
- **miroe**: 우리가 직접 빌드하고, 어떤 소스와 패치로 만들었는지 누구나 다시 빌드해서 확인할 수 있게 해요. 모든 부품은 SHA-256으로 고정해요(Miro가 이미 하는 방식이에요).

### 14. 처음 실행이 느림 (난이도 하)

- **문제**: Windows 환경(C: 드라이브)을 처음 만들 때 wineboot, Mono, Gecko 설치가 오래 걸려요.
- **miroe**: 미리 만들어 둔 환경 틀을 APFS 복제로 순식간에 펼쳐요. Miro의 복구 지점에서 쓰는 방식이에요.

### miroe도 못 푸는 것

- **커널 안티치트**(Valorant, Fortnite 등): Mac에서는 원리상 불가능해요. 우회하면 계정 정지 위험이 있어요. 실행 전에 알려 주기만 해요.
- **Windows 드라이버가 필요한 프로그램**, **16비트 프로그램**
- 다른 프로그램의 Intel 코드를 번역하지 않고 실행하는 것: 번역은 FEX나 Rosetta가 맡아요.

## miroe 설계 원칙

1. **애플 실리콘 전용**: ARM64 호스트 하나만 생각해요. Intel Mac, Linux, 32비트 호스트는 고려하지 않아요.
2. **Wine을 재료로, 약한 층은 Mac 고유 기술로 교체**: 위 목록에서 보듯 문제는 특정 층(동기화, 창, 입력, 동영상, 글꼴, 메모리)에 몰려 있어요. Windows API 전체를 새로 짜는 대신, 이 층들을 Metal, CoreAudio, GameController, VideoToolbox, Core Text 같은 Mac 기술로 바꿔요.
3. **공식 Wine을 따라가요**: 새 Wine 버전이 나오면 우리 패치를 다시 올리고, 화면 없는 테스트와 벤치마크로 확인해요. 공식 통로가 생기면 우리 우회(예: Miro Metal Bridge)는 은퇴시켜요.
4. **측정이 먼저**: 고치기 전에 재고, 고친 뒤에 다시 재요. 숫자로 나아지지 않으면 넣지 않아요.
5. **게임 없이 테스트**: 사용자 게임은 테스트에 쓰지 않아요. 직접 만든 중립 테스트 프로그램만 써요.

## 단계

1. **측정 도구**: 1프레임 시간이 Rosetta, Wine 경계, 그래픽 변환 중 어디서 쓰이는지 나눠 재요. 입력 지연, 메모리 측정도 만들어요.
2. **miroe 0.1**: 공식 Wine 소스로 애플 실리콘 전용 빌드를 자동화하고, Miro Metal Bridge와 DXMT를 넣어요. Miro의 실험 엔진으로 연결해요.
3. **빠른 성과**: 빠른 동기화(3번), 한중일 글꼴 연결(10번), 컨트롤러 지연(7번), 게임 모드(6번)
4. **ARM64 + FEX**: Rosetta 없이 실행(1·2번). macOS 28 전에 끝내야 해요.
5. **Mac 고유 층**: 동영상 하드웨어 디코딩(9번), 메모리 보고(11번), 전체 화면(6번)
