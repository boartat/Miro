# miroe 기반 구성 검토 (2026-11-27)

miroe는 **애플 실리콘 전용 ARM64 네이티브 Wine + FEX 엔진**이에요. 여러 운영체제와 CPU를 두루 지원하는 대신 애플 실리콘 하나만 지원하고, 그만큼 병목을 없애고 성능을 올리는 걸 목표로 하는 차세대 엔진이에요.

- 모든 연구와 최적화는 ARM64 네이티브 엔진에서 해요.
- 기존 x86_64 엔진(Miro 1.2의 CrossOver 26.3 트리 Wine 11과 Wine 7.7 GPTK, 실습실의 WineHQ 11.21)은 **비교 대조군으로만** 써요. 여기에 miroe 패치를 넣지 않아요.

## 1. upstream Wine의 ARM64 macOS 지원 (MR !12716)

2026-11-26에 병합됐어요(Brendan Shanks, CodeWeavers). 커밋 10개예요.

| 커밋 | 내용 |
| --- | --- |
| f858e69b, 0864ebec, 853419aa, d6e8b8ee | **x18 레지스터**: macOS는 x18을 시스템용으로 쓰고 문맥 전환 때 0으로 지워요. Windows는 x18에 TEB를 둬요. macOS 26.5의 공개 API `os_set_custom_x18_abi_enabled()`로 PE 코드에 들어갈 때 켜고, 시그널 처리기와 시스템 호출에서 꺼요 |
| a5c374e5 | **4K 페이지 모드**: 로더를 `posix_spawnattr_set_4k_page_size_np()`(macOS 26 공개 API)로 다시 실행해서, 프로세스가 Windows와 같은 4K 페이지를 써요 |
| c76ef55e | **아래 8GB 예약**: `__PAGEZERO`를 8GB로 잡아 32비트·고정 주소 프로그램 자리를 확보해요. macOS 27이 필요해요(26.5에서는 dyld 공유 캐시 위치 때문에 안 돼요) |
| 8f5129a0, 3803d166, e973273c | **서명과 권한**: 로더를 `.app` 묶음으로 만들고, 빌드할 때 `com.apple.developer.cross-architecture-support` 권한과 개발용 provisioning profile로 서명해요(`--enable-codesign-identity`, `--enable-provisioning-profile`). [위키](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-Building/ARM64-Provisioning-Profiles)에 따르면 지금은 **유료 개발자 계정이 필요**해요 |
| 4fd5fe15 | 문서: ARM64는 macOS 27 필요 |

같은 시기 upstream의 관련 변경:
- 9d639791 (Julliard, 11-24): **W^X 강제 플랫폼 대응**. 쓰기 가능한 페이지는 실행 권한 없이 두고, 실행 fault가 나면 읽기+실행으로, 쓰기 fault가 나면 다시 읽기+쓰기로 바꿔요
- b4c6b37e: 실행 권한 강제는 32비트 주소에만, 59f10f47: 완화 옵션으로 DEP 강제, dedead43: Rosetta 우회는 x86_64 macOS에서만

이 Mac(macOS 27.2, SDK 27.2)에는 필요한 API가 모두 있어요. 서명 권한만 빠져 있어요.

## 2. Hadron 기반과 비교

지금 실습실의 ARM64 엔진은 Hadron 고정 커밋(Wine 9f8c4ae, upstream보다 280커밋 뒤)에 Hadron Wine 패치 55개를 얹은 거예요. 권한이 없어서 64비트만 도는 dev 엔진(`KUSER_SHARED_DATA`를 4GB 위로 옮김)을 써 왔어요.

| | Hadron 기반 (지금) | upstream (병합 후) |
| --- | --- | --- |
| 페이지 크기 | 16K. 부분 페이지 문제를 패치로 막음(0033·0034·0035, findings #42·#43) | **4K**. Windows와 같아서 부분 페이지 문제가 원리상 없어요 |
| 4GB 아래 메모리 | 권한이 있으면 0001·0052, 없으면 dev 엔진(64비트만) | 8GB PAGEZERO + 권한 |
| x18 | 0004 | f858e69b 외 3개 (같은 API) |
| W^X | 0002·0006(동시에 뒤집기 처리), 0011(FEX JIT는 MAP_JIT) | 9d639791 (동시성 처리는 확인 필요) |
| 서명 | 0008 | 빌드 옵션으로 공식 지원 |
| FEX 연결 | Wine의 ARM64EC 지원 + Hadron FEX 패치 7개 | Wine 쪽 같음. FEX의 macOS 지원은 upstream FEX에 없어서 Hadron FEX 패치가 여전히 필요해요 |
| 하드웨어 TSO | 0010 (`thread_set_x86_64_compat`, 같은 권한 필요) | 없음 |

### Hadron Wine 패치 55개의 처리

| 분류 | 패치 | 처리 |
| --- | --- | --- |
| **upstream이 대신함** | 0001, 0052 (PAGEZERO), 0004 (x18), 0008 (권한·서명), 0002·0006 (W^X) | 버려요. 0006의 동시 뒤집기는 upstream에서 같은 문제가 나는지 테스트로 확인해요 |
| **권한이 생기면 필요 없음** | 0003 (dev 엔진용 `KUSER_SHARED_DATA`) | 버려요 |
| **4K 페이지에서 필요 없을 가능성** | 0033, 0034, 0035 (부분 페이지), 0024, 0051, 0005, 0042, 0054 (주소 공간 배치) | 4K + 8GB PAGEZERO에서 각 문제의 재현 테스트를 돌려 보고, 재현되는 것만 옮겨요 |
| **FEX에 필요함** | 0010 (하드웨어 TSO), 0011 (FEX JIT의 MAP_JIT), 0020 (ID 레지스터), 0038 (`RtlIsEcCode`), 0055 (풀기) | 옮겨요 (출처 표기) |
| **Metal 그래픽에 필요함** | 0007, 0012, 0014 (DXMT가 쓰는 winemac 함수 표와 외부 Metal 뷰), 0023·0027 (EGL OpenGL), 0017 | 옮겨요. upstream !11058(ExtEscape)이 병합되면 그쪽으로 바꿔요 |
| **화면·창·입력** | 0013, 0016, 0018, 0021, 0026, 0028~0032, 0036, 0037, 0041, 0043~0046 | 필요한 것만 골라 옮겨요 |
| **Steam·Hadron 앱 전용** | 0009, 0025, 0039, 0040, 0022, 0050 | 대부분 옮기지 않아요. Miro에 필요한지 따로 봐요 |
| **기타 정확성** | 0015, 0019, 0047, 0048, 0049, 0053 | 테스트로 확인하고 옮겨요 |

## 3. 권장 구성

| 층 | 선택 | 근거 |
| --- | --- | --- |
| Wine | **upstream Wine master** (!12716 이후 커밋 하나로 고정), ARM64, macOS 27, 4K 페이지, 권한 서명 | 공식 지원이 생겨서 Hadron 고정 커밋을 따라갈 이유가 없어졌어요. 4K 페이지로 16K 문제들이 사라지고, 앞으로 upstream을 따라가기 쉬워요 |
| Hadron 패치 | 위 표의 "옮겨요"만, 한 번에 하나씩, 테스트와 함께 | 꼭 필요한 것만 유지해요 |
| FEX | upstream FEX 고정 커밋 + Hadron FEX macOS 패치 7개 (MIT) | macOS 지원은 아직 Hadron에만 있어요 |
| D3D10/11/12 | **Mullion을 기본 그래픽 백엔드로** (LGPL, DXMT 포크, D3D12 FL 12_2) + MUMA 이식 패치 | 2026-11-27 사용자 결정. 아래 5장의 검증 결과. D3DMetal에 기대지 않는 오픈소스 D3D12 |
| D3D9 / OpenGL / Vulkan | mtld3d (zlib) / WineMetalGL (LGPL) / KosmicKrisp (MIT) | 이미 ARM64 Wine에서 쓰이고 있어요 |
| 동기화 | msync 계열 채택 연구 (MetalSharp-Wine의 LGPL Wine 변경) | PROBLEMS.md Y1 (Unity 스레드 시간의 55%) |
| 빌드 | miroe 자체 스크립트 (`scripts/`), llvm-mingw | Hadron 스크립트에서 출발했지만 Hadron 앱 전용 부분은 빼요 |
| 대조군 | x86_64 엔진들, 지금의 Hadron dev 엔진 | 같은 테스트로 비교만 해요 |

**순서**
1. 개발자 계정이 열리면 App ID(예: `app.miro.miroe`)와 개발용 provisioning profile을 만들어요. 계정에서 해야 하는 부분은 사용자가 직접 해요.
2. upstream Wine master를 ARM64로 빌드하고 서명해요. 64비트 테스트, 32비트 테스트(W1 확인 포함), MUMA 테스트를 돌려요.
3. FEX 패치와 꼭 필요한 Hadron 패치를 옮기고, 하나 옮길 때마다 같은 테스트를 돌려요.
4. 그래픽 경로(DXMT / Mullion)를 비교해서 정하고, MUMA를 그 위에 맞춰요.
5. 그다음 연구 과제(Y1 동기화, F1 상수 버퍼, L1 하드웨어 TSO)로 가요.

**위험**
- !12716은 병합된 지 하루라서 버그가 있을 수 있어요. 고정 커밋을 두고, 문제가 나면 Hadron 패치와 비교해요.
- 권한은 개발용 profile이라 등록한 Mac에서만 돌아요. 다른 사람에게 배포하려면 따로 방법을 찾아야 해요(Developer ID 배포에서 이 권한을 쓸 수 있는지는 아직 확인하지 못했어요).
- 4K 페이지 모드는 macOS가 x86 호환용으로 만든 기능이라, ARM64 네이티브 코드에서 성능 차이가 있는지 재 봐야 해요.

## 4. W1과 ARM64

W1(DEP가 꺼진 32비트 프로그램의 슬라이드쇼, DXMT #161)은 **Intel Wine + Rosetta에서의 독립 연구 성과로 보존**해요. Miro 1.2의 엔진에는 넣지 않아요.

ARM64에서는 같은 문제가 구조적으로 생기지 않을 것으로 봐요.
- 원인은 "쓰기+실행 메모리 위의 Metal no-copy 버퍼"예요. ARM64 macOS는 보통 메모리에 쓰기+실행을 허락하지 않아요(`mmap`·`mprotect` 모두 Permission denied, [`tools/w1/metal-arm64-probe.m`](tools/w1/metal-arm64-probe.m)).
- upstream(9d639791)과 Hadron(0002)은 모두 쓰기 가능한 페이지를 실행 권한 없이 두고, 실행할 때만 읽기+실행으로 바꿔요. placed 메모리는 실행되지 않으니 계속 읽기+쓰기예요.
- 읽기+실행 메모리를 GPU가 써도 다음 CPU 접근은 0.004ms였어요(멈춤 없음). MAP_JIT 메모리는 프로브가 SIGBUS로 끝나 재지 못했어요. MAP_JIT는 FEX의 JIT 코드 버퍼에만 쓰여서 placed 메모리와 겹치지 않아요.
- **실제 32비트 프로그램으로 하는 확인은 권한이 생긴 뒤에 해요.** 지금 dev 엔진은 64비트만 돌아요. 그때 문제가 없으면 W1 패치는 miroe에 넣지 않아요.

## 5. 그래픽 백엔드: Mullion 채택 검증 (2026-11-27)

사용자 결정으로 Mullion을 기본 그래픽 백엔드로 정했어요. D3DMetal(닫힌 소스)에 기대지 않고 오픈소스로 D3D12까지 가는 길이에요. 실습실 ARM64 엔진(Hadron dev, 64비트)에 Mullion `0f22b2c`를 올려서 확인했어요.

**빌드**: Mullion은 DXMT와 구조가 같아요(`src/dxmt` → `src/mullion`). ARM64X 링크 오류 하나만 Hadron의 DXMT 패치를 그대로 써서 고쳤어요([`patches/mullion/0001`](patches/mullion)). D3D12 DLL(`d3d12.dll`, `d3d12core.dll`)도 같이 빌드돼요.

**D3D12 기본 동작** ([`Engine/tests/c/d3d12-smoke-test.c`](../tests/c/d3d12-smoke-test.c), 창·셰이더 없음): 기능 수준 **12_2**를 알리고, 렌더 타깃 지우기 → 복사 → 읽기의 65,536픽셀이 모두 맞아요. 프레임당 0.21ms.

**D3D12 셰이더** ([`Engine/tests/c/d3d12-shader-test.c`](../tests/c/d3d12-shader-test.c), HLSL을 실행 중에 SM 5.0 DXBC로 컴파일): 루트 상수를 쓰는 픽셀 셰이더 그리기, 셰이더용 디스크립터 테이블과 정적 샘플러로 텍스처 읽기, UAV 버퍼에 쓰는 컴퓨트 셰이더가 **모두 정확해요**(65,536픽셀 ×2, 1,024값). 원래 Mullion과 MUMA 판 모두 같아요. 그리기 + 펜스 대기 0.21ms. 그래픽 파이프라인은 처음 1회 39.8ms, 셰이더 캐시가 찬 뒤 1.5ms. 

**SM 6 (DXIL) 셰이더** ([`Engine/tests/c/d3d12-sm6-test.c`](../tests/c/d3d12-sm6-test.c), 셰이더는 [`sm6/`](../tests/c/sm6)의 HLSL을 Microsoft DXC 1.9.2609로 미리 컴파일한 서명된 DXIL): 장치는 **셰이더 모델 6.7**, 웨이브 연산(32레인), 네이티브 16비트, 리소스 바인딩 Tier 3을 알려요. SM 6.0 그리기(65,536픽셀), SM 6.0 웨이브 연산(레인 번호·누적 합·웨이브 합, 256스레드), SM 6.2 16비트 정수·실수(256값), SM 6.6 디스크립터 힙 직접 접근(`ResourceDescriptorHeap[]`, 1,024값)이 **모두 정확해요**. 원래 Mullion과 MUMA 판이 같아요.
- DXC는 지금 dev 엔진에서 돌지 않아요(`KUSER_SHARED_DATA`를 고정 주소로 읽는데, dev 엔진은 그 영역을 4GB 위로 옮겼어요). 그래서 Intel 실습실 엔진에서 미리 컴파일했어요. 서명 권한이 생긴 엔진에서는 문제가 없을 거예요.
- 아직 확인하지 않은 것: 메시 셰이더, 레이 트레이싱, SM 6.7의 고급 텍스처 연산(Mullion README에서도 미완성)

**Mullion 자체의 메모리 관리** (`src/mullion/mullion_memory.*`, `mullion_heartbeat.*`)
- 한도: Metal 작업 세트의 95%. macOS 26 이하에서는 넘는 할당을 거부해요(커널 패닉 방지).
- 예산: 메모리 압력에 따라 3/4, 1/2로 낮아져요. 게임에 알려 주는 DXGI 예산이에요.
- 하트비트: GPU가 쉬는 동안 1MB 이상 버퍼를 residency set에 넣고 상주를 요청해요(쉬고 난 첫 프레임의 멈춤 방지).
- **예비 블록은 회수하지 않아요.** 그래서 #260 문제가 그대로 있어요(아래 표의 "원래").

**MUMA와의 관계**
- 겹치지 않고 서로 보완해요. Mullion은 "얼마까지 쓸지"를 정하고, MUMA는 "안 쓰는 예비 블록을 돌려주는" 일을 해요.
- 이식하면서 MUMA v2의 예산을 Mullion의 압력 반영 예산으로 바꿨어요. 시스템 메모리가 모자라면 예비 블록부터 풀려요.
- **충돌 한 곳**: 하트비트가 purgeable 예비 블록을 계속 상주시키면 purgeable 효과가 없어져요(아래 표). 이식판은 예비 블록이 purgeable인 동안 하트비트 집합에서 빼고, 다시 쓸 때 넣어요.
- Mullion은 할당 하나에 이름(name) 여러 개를 담을 수 있어서, 예비 블록 크기를 버퍼가 아니라 할당 기준으로 세요.

| GPU 메모리 (MB) | DXMT 원래 | DXMT + MUMA v2 | Mullion 원래 | **Mullion + MUMA** |
| --- | ---: | ---: | ---: | ---: |
| 동적 버퍼 몰아치기 뒤 | 920 | 308 | 923 | **308** |
| 제출을 멈춘 앱 | 920 | 308 | 923 | **308** |
| 64MB 동적 텍스처 | 968 | 196 | 971 | **199** |
| 예비 블록 60초 유지, purgeable 켬 | — | — | — | **308** |
| 같은 조건, 하트비트 집합에 그대로 둠 | — | — | — | 923 |
| 같은 조건, purgeable 끔 | — | — | — | 923 |

| 게임 비슷한 테스트 (3회) | Mullion 원래 | **Mullion + MUMA** |
| --- | --- | --- |
| 교전 1 뒤 메모리 (GPU) | 873 MB (584) | **594 MB (303)**: GPU −48% |
| 메뉴 메모리 (GPU) | 912 MB (629) | **579 MB (294)**: GPU −53% |
| 교전 중 최대 | 996 / 1,045 MB | 1,043 / 1,165 MB (실행마다 범위 안) |
| 교전 2 프레임 평균 / p99 / 최대 | 1.80 / 9.83 / 11.70 ms | 1.75 / 8.19 / 11.40 ms |
| 작은 discard 2000번 (번갈아 5회) | 3.117 ms (3.067~3.159) | 3.136 ms (3.064~3.219): 차이 없음 |

데이터 확인(재사용된 예비 블록의 내용)은 모든 경우 통과했어요.

**결론**: MUMA는 Mullion에 이식할 수 있고, Mullion의 메모리 관리와 충돌하지 않게 맞췄어요(하트비트 한 곳). 효과는 DXMT에서와 같아요. 속도 차이는 없어요(처음 따로 잰 3.229 / 3.308ms는 측정 시점 차이였고, 번갈아 재니 범위가 겹쳤어요). 남은 것: 메시 셰이더·레이 트레이싱 테스트, 실제 메모리 압력 아래 동작, 하트비트가 지키려는 "쉬고 난 첫 프레임"과 MUMA 회수의 관계 측정.

## 6. upstream Wine ARM64 빌드 준비 (2026-11-27)

[`scripts/build-wine-upstream.sh`](scripts/build-wine-upstream.sh)로 upstream Wine `ecca8e7552`(11.22-280, `sources.conf`의 `wine-upstream`)를 aarch64 + arm64ec + i386 PE로 **빌드했어요**. 로더는 `wine.app` 묶음으로 만들어져요. 서명 정보 없이 빌드해서 ad-hoc 서명이고, 실행하면 macOS가 바로 종료시켜요(exit 137). 예상대로예요.

개발자 계정이 열리면 할 일:
1. App ID와 개발용 provisioning profile을 만들어요(사용자가 직접, 위키의 순서).
2. `CODESIGN_IDENTITY="Apple Development: …" PROVISIONING_PROFILE=… scripts/build-wine-upstream.sh`로 다시 서명해서 빌드해요.
3. FEX(Hadron FEX 패치)와 Mullion + MUMA를 이 엔진에 올리고, 64비트·32비트·D3D12 테스트를 돌려요.
