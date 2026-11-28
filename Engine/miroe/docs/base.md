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
| 동기화 | msync 계열 채택 연구 (MetalSharp-Wine의 LGPL Wine 변경) | problems.md Y1 (Unity 스레드 시간의 55%) |
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
- 원인은 "쓰기+실행 메모리 위의 Metal no-copy 버퍼"예요. ARM64 macOS는 보통 메모리에 쓰기+실행을 허락하지 않아요(`mmap`·`mprotect` 모두 Permission denied, [`tools/w1/metal-arm64-probe.m`](../tools/w1/metal-arm64-probe.m)).
- upstream(9d639791)과 Hadron(0002)은 모두 쓰기 가능한 페이지를 실행 권한 없이 두고, 실행할 때만 읽기+실행으로 바꿔요. placed 메모리는 실행되지 않으니 계속 읽기+쓰기예요.
- 읽기+실행 메모리를 GPU가 써도 다음 CPU 접근은 0.004ms였어요(멈춤 없음). MAP_JIT 메모리는 프로브가 SIGBUS로 끝나 재지 못했어요. MAP_JIT는 FEX의 JIT 코드 버퍼에만 쓰여서 placed 메모리와 겹치지 않아요.
- **실제 32비트 프로그램으로 하는 확인은 권한이 생긴 뒤에 해요.** 지금 dev 엔진은 64비트만 돌아요. 그때 문제가 없으면 W1 패치는 miroe에 넣지 않아요.

## 5. 그래픽 백엔드: Mullion 채택 검증 (2026-11-27)

사용자 결정으로 Mullion을 기본 그래픽 백엔드로 정했어요. D3DMetal(닫힌 소스)에 기대지 않고 오픈소스로 D3D12까지 가는 길이에요. 실습실 ARM64 엔진(Hadron dev, 64비트)에 Mullion `0f22b2c`를 올려서 확인했어요.

**빌드**: Mullion은 DXMT와 구조가 같아요(`src/dxmt` → `src/mullion`). ARM64X 링크 오류 하나만 Hadron의 DXMT 패치를 그대로 써서 고쳤어요([`patches/mullion/0001`](../patches/mullion)). D3D12 DLL(`d3d12.dll`, `d3d12core.dll`)도 같이 빌드돼요.

**D3D12 기본 동작** ([`Engine/tests/c/d3d12-smoke-test.c`](../../tests/c/d3d12-smoke-test.c), 창·셰이더 없음): 기능 수준 **12_2**를 알리고, 렌더 타깃 지우기 → 복사 → 읽기의 65,536픽셀이 모두 맞아요. 프레임당 0.21ms.

**D3D12 셰이더** ([`Engine/tests/c/d3d12-shader-test.c`](../../tests/c/d3d12-shader-test.c), HLSL을 실행 중에 SM 5.0 DXBC로 컴파일): 루트 상수를 쓰는 픽셀 셰이더 그리기, 셰이더용 디스크립터 테이블과 정적 샘플러로 텍스처 읽기, UAV 버퍼에 쓰는 컴퓨트 셰이더가 **모두 정확해요**(65,536픽셀 ×2, 1,024값). 원래 Mullion과 MUMA 판 모두 같아요. 그리기 + 펜스 대기 0.21ms. 그래픽 파이프라인은 처음 1회 39.8ms, 셰이더 캐시가 찬 뒤 1.5ms. 

**SM 6 (DXIL) 셰이더** ([`Engine/tests/c/d3d12-sm6-test.c`](../../tests/c/d3d12-sm6-test.c), 셰이더는 [`sm6/`](../../tests/c/sm6)의 HLSL을 Microsoft DXC 1.9.2609로 미리 컴파일한 서명된 DXIL): 장치는 **셰이더 모델 6.7**, 웨이브 연산(32레인), 네이티브 16비트, 리소스 바인딩 Tier 3을 알려요. SM 6.0 그리기(65,536픽셀), SM 6.0 웨이브 연산(레인 번호·누적 합·웨이브 합, 256스레드), SM 6.2 16비트 정수·실수(256값), SM 6.6 디스크립터 힙 직접 접근(`ResourceDescriptorHeap[]`, 1,024값)이 **모두 정확해요**. 원래 Mullion과 MUMA 판이 같아요.
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

[`scripts/build-wine-upstream.sh`](../scripts/build-wine-upstream.sh)로 upstream Wine `ecca8e7552`(11.22-280, `sources.conf`의 `wine-upstream`)를 aarch64 + arm64ec + i386 PE로 **빌드했어요**. 로더는 `wine.app` 묶음으로 만들어져요. 서명 정보 없이 빌드해서 ad-hoc 서명이고, 실행하면 macOS가 바로 종료시켜요(exit 137). 예상대로예요.

## 7. 서명된 upstream ARM64 Wine에서 FEX 실행 (2026-11-27)

유료 개발자 계정으로 App ID `app.miro.miroe`(Cross-architecture Compatibility Framework 켬), 이 Mac 등록, 개발용 provisioning profile을 만들었어요. 계정 화면에서 체크 하나로 켜지고 Apple에 따로 신청할 필요가 없었어요. 기존 Apple Development 인증서가 이미 이 팀 것이라 새 인증서도 필요 없었어요.

[`scripts/sign-engine.sh`](../scripts/sign-engine.sh)가 빌드된 엔진의 `wine.app` 번들 ID를 `app.miro.miroe`로 바꾸고, profile을 넣고, upstream의 권한 파일(`loader/wine_arm64_entitlements.plist`)로 서명해요. 그다음 Hadron 패치를 올린 FEX를 `xtajit.dll`(i386, wow64)·`xtajit64.dll`(x86_64, ARM64EC)로 넣어요. profile이 앱 식별자를 대신 주므로 권한 파일에 따로 더할 건 없어요.

| 확인 | 결과 |
| --- | --- |
| 로더 실행 | macOS가 더 이상 종료시키지 않음. 새 prefix 만들기, `cmd` 실행 정상 |
| 32비트 x86 (FEX wow64) | DEP가 꺼진 실행 테스트 9가지 **모두 정확** (`DEP-OFF EXEC OK`) |
| x86_64 (FEX ARM64EC) | Microsoft DXC가 SM 6.0 셰이더를 정상 컴파일. dev 엔진에서 나던 `KUSER_SHARED_DATA` 충돌이 사라졌어요 |

알게 된 것:
- prefix는 FEX를 넣은 **뒤에** 만들어야 해요. Wine은 시스템 파일이 없을 때 내장 DLL로 대신하는 걸 prefix를 처음 만들 때만 해요. 그래서 FEX 없이 만든 prefix는 `syswow64`가 비어서 32비트 프로그램이 `kernel32.dll`을 못 찾아요. 고치려면 FEX DLL을 `system32`에 복사하고 `WINEBOOTSTRAPMODE=1 wine wineboot -u`를 한 번 실행해요.
- 테스트할 때 `perl`이나 `timeout` 같은 시스템 프로그램으로 감싸면 SIP가 `DYLD_*` 변수를 지워서 FreeType을 못 찾아요. 서명 때문이 아니에요.

### Mullion + MUMA를 올린 결과

[`scripts/build-mullion-upstream.sh`](../scripts/build-mullion-upstream.sh)로 Mullion + MUMA를 upstream Wine 빌드에 맞춰 ARM64X(arm64ec)와 32비트(win32)로 빌드해서 서명된 엔진에 넣었어요. 32비트 DLL은 같은 aarch64 유닉스 라이브러리를 Wine의 wow64로 불러요. Mullion을 넣은 뒤 이미 있던 prefix는 `wine wineboot -u`로 한 번 갱신해야 `winemetal.dll`이 들어가요.

| 확인 | 결과 |
| --- | --- |
| D3D12 기본·SM 5.0 셰이더 (ARM64) | 기능 수준 12_2, 모든 픽셀·값 정확 |
| SM 6.0~6.6 (ARM64) | 모두 정확. 셰이더는 **이 엔진에서 x64 DXC로 컴파일**했고, Intel 실습실에서 만든 것과 바이트까지 같아요 |
| MUMA, 동적 버퍼 뒤 GPU 메모리 | 308MB (Hadron dev 엔진과 같음, 원래 Mullion 923MB) |
| MUMA, 동적 텍스처 뒤 | 199MB (원래 971MB) |
| MUMA, 게임형 테스트 메뉴 | 296MB (원래 582MB) |
| MUMA, x86_64 프로그램 (FEX ARM64EC) | 308MB. ARM64 프로그램과 같아요 |

**W1이 ARM64에서 생기는지**: 32비트 게임형 테스트(D3D11, Mullion + MUMA, FEX wow64)를 3번씩 돌렸어요.

| 엔진 | DEP 꺼짐 (nonx) | DEP 켜짐 (nx) |
| --- | ---: | ---: |
| Intel Wine 11.21 + DXMT, Rosetta (대조군) | 36프레임 | 2,201프레임 |
| 같은 엔진 + W1 패치 | 2,002프레임 | — |
| **upstream ARM64 Wine + FEX + Mullion** | **2,182프레임** (2,184 / 2,181 / 2,182) | 2,180프레임 |

ARM64 엔진에서는 DEP가 꺼져도 느려지지 않아요. FEX는 x86 코드를 번역해서 따로 실행하므로, 게임 메모리에 실제 실행 권한을 붙일 일이 없어서 Rosetta의 조건이 생기지 않아요. 그래서 **W1 패치는 ARM64 엔진에 넣지 않아요**(Rosetta 연구 성과로만 보존).

다음: Miro 앱의 miroe 엔진을 이 기반(서명된 upstream Wine + FEX + Mullion + MUMA)으로 바꾸고, 32비트 게임 차단을 풀어요.

## 8. HTTPS·Vulkan을 넣은 엔진 (miroe-2, 2026-11-28)

앞 엔진의 `configure.log`에 GnuTLS와 MoltenVK가 없었어요. 그래서 Windows 프로그램의 HTTPS(schannel)와 Vulkan이 모두 안 됐어요. Homebrew의 `gnutls`(3.8.14, LGPL 2.1+)와 `molten-vk`(1.4.2, Apache 2.0)를 설치하고 `MIROE_RECONFIGURE=1 scripts/build-wine-upstream.sh`로 다시 빌드했어요. `Scripts/install_miroe_engine.sh`는 이제 Wine이 이름으로 여는 라이브러리(FreeType, GnuTLS, MoltenVK)와 그 의존 라이브러리 14개를 엔진 안에 복사하고, 라이선스 파일을 `miro/licenses`에 같이 넣어요. 실행 중에는 Homebrew가 필요 없어요.

테스트 프로그램(직접 작성, `/Users/Shared/miroe-lab/tests/engine2`)으로 확인했어요. 사용자 게임은 쓰지 않았어요.

| 확인 | 이전 엔진 | miroe-2 (ARM64 / x86_64 / 32비트) |
| --- | --- | --- |
| HTTPS (WinHTTP → store.steampowered.com) | 실패 `SEC_E_SECPKG_NOT_FOUND` | **200 OK** (1405 / 478 / 580ms) |
| Vulkan (`vulkan-1.dll` → MoltenVK) | 실패 `VK_ERROR_INITIALIZATION_FAILED` | **Apple M4 Pro, Vulkan 1.3** (세 가지 모두) |
| D3D9, WineD3D (OpenGL) | — | 2,383 / 2,366 / 1,781 fps |
| D3D9, WineD3D (Vulkan 렌더러 → MoltenVK) | — | 212 / 216 / 223 fps |
| D3D9, DXVK 3.2 | — | **어댑터 없음**: MoltenVK에 필수 기능이 없어요 |

### DXVK가 MoltenVK에서 안 되는 이유

[`scripts/build-dxvk.sh`](../scripts/build-dxvk.sh)로 DXVK 3.2의 d3d8·d3d9를 ARM64X(64비트, FEX 없이 네이티브)와 i386(32비트)으로 빌드했어요. 빌드는 되지만 DXVK가 기기를 거절해요. DXVK의 필수 기능 목록(`src/dxvk/dxvk_device_info.cpp`)을 MoltenVK 1.4.2가 알려 주는 기능과 비교하면 다섯 개가 없어요.

| DXVK 필수 기능 | MoltenVK | 고칠 수 있나 |
| --- | --- | --- |
| `geometryShader` | 없음 | D3D9은 `ProcessVertices`(소프트웨어 정점 처리)에만 써요. 선택 기능으로 바꿀 수 있어요 |
| `shaderCullDistance` | 없음 | D3D9에는 없는 기능. 선택으로 바꿀 수 있어요 |
| `depthClipEnable` (VK_EXT_depth_clip_enable) | 확장 없음 | 깊이 클리핑을 셰이더로 흉내 내야 해요 |
| `robustBufferAccess2` | 없음 | 범위 밖 읽기를 0으로 만드는 처리를 DXVK가 직접 해야 해요 |
| `nullDescriptor` | 없음 | DXVK 2.0부터 빈 슬롯을 이걸로 처리해요. 더미 리소스로 되돌리는 큰 수정이에요 |

`nullDescriptor`와 `robustBufferAccess2`는 DXVK 2.x 이후 리소스 바인딩 구조의 바탕이라, 줄 몇 개로 고칠 수 없어요. 그래서 이번 엔진에는 DXVK를 넣지 않았어요. D3D8·9는 지금 가장 빠른 WineD3D(OpenGL)로 돌아가요. 다음 방법 중 하나를 골라야 해요.

1. DXVK를 MoltenVK에 맞게 고치는 miroe 패치 (위 다섯 가지). 가장 큰 작업이에요.
2. MoltenVK가 `VK_EXT_robustness2`의 `nullDescriptor`를 지원할 때까지 기다리기.
3. D3D9를 Metal로 바로 옮기는 별도 구현(예: Mullion이 D3D10~12를 하듯이).

### Windows Steam을 miroe에서

Miro-CX에 설치된 Steam 프로그램 파일만(로그인·계정 정보인 `config`, `userdata`는 빼고) 시험용 prefix에 복사해서 miroe-2로 실행했어요.

| 단계 | 결과 |
| --- | --- |
| 32비트 `steam.exe` (FEX wow64) | 실행됨. 업데이트 창 표시 |
| 업데이트 확인 (HTTPS) | 매니페스트 61초 만에 받음. CrossOver 기반 엔진에서도 61초. 업데이트 설치 후 스스로 재시작(종료 코드 42) |
| 64비트 `steamwebhelper.exe` (Chromium, FEX ARM64EC) | 실행됨. Mullion으로 D3D11 기능 수준 11_1 장치를 만듦 |
| 로그인 페이지 | 0.3초 만에 불러오고 로그인 서버와 통신까지 함 (`steamui_login.txt`) |
| **화면** | **검은색**. 기본, `-cef-disable-gpu-compositing`, `-cef-use-vulkan`, `-cef-disable-gpu` 모두 같아요 |

처음에는 페이지는 그려지는데 창에 화면이 전달되지 않았어요.

**원인**: Chromium은 GPU 프로세스에서 그린 화면을, 브라우저 프로세스가 가진 최상위 창 안에 넣어요. Mullion은 화면을 보여 줄 Cocoa 창을 자기 프로세스 안에서만 찾았고, 못 찾으면 로그만 남겼어요(`winemetal: no window to present 0x30128 in`, Steam 한 번 실행에 5번). GPU를 끈 경우도 같은 종류예요. 시험 프로그램(`tests/engine2/xproc.c`)으로 확인해 보니, 이 Wine에서는 다른 프로세스의 창에 그리는 GDI 그림이 모두 사라져요(최상위 창에 직접, 또는 그 안에 만든 자기 자식 창에). upstream Wine에는 프로세스 간 화면 공유(`d3dkmt_swapchain`)가 새로 생겼지만, 텍스처를 넘기는 부분이 EGL(리눅스)에만 있어서 macOS에서는 쓸 수 없어요.

**고친 방법** ([`patches/mullion/0003`](../patches/mullion/0003-winemetal-present-into-a-top-level-window-of-another.patch)): 창이 다른 프로세스 것이면, Mullion이 그리는 프로세스에 테두리 없는 패널을 만들어 Metal 화면을 넣어요. 패널은 클릭과 키 입력을 통과시키고 활성화되지 않아요. 다른 Wine 프로세스의 화면 위 창들 중에서 주인 창을 찾아, 그 바로 위에 붙여 둬요. 0.1초마다 주인 창의 위치와 순서를 확인해서 따라가요.

| 확인 (시험용 prefix, 사용자 계정 없음) | 결과 |
| --- | --- |
| 로그인 화면 | **그려짐** (한국어 글자, QR 코드까지). 처음 실행 76초, 다음부터 24초 |
| 위치 | 주인 창과 정확히 같음 (406,242) |
| 창 이동 (다른 프로세스에서 `SetWindowPos`) | 따라감 |
| 최소화 / 복원 | 같이 숨고 같이 나타남 |
| 다른 창이 위에 열림 | 순서: 다른 창 → 패널 → Steam 창. 가려진 부분이 맞게 보여요 |
| 같은 프로세스 창 (D3D11 게임형 테스트) | 기존 방식 그대로, 모든 단계 정상 |

아직 확인하지 못한 것: 실제 마우스 클릭과 키보드 입력이 패널을 통과해 Steam에 닿는지(화면 제어 허가가 필요해서 사용자 확인 필요). 여러 화면, 전체 화면 전환, Spaces 이동도 아직이에요.

**결론**: Steam 화면 전달 문제는 풀렸어요. 입력 통과를 확인하면 Steam을 miroe로 옮길 수 있어요. 단일 엔진 전환의 남은 조건은 (1) Steam 입력·로그인 확인 후 Steam을 miroe로 옮기기, (2) D3D8·9 백엔드 결정, (3) 공개 배포용 Developer ID 서명이에요.

### 한글이 네모나 빈칸으로 나오는 문제 (GDI 글꼴 연결)

Steam 업데이트 창처럼 Tahoma로 그리는 한국어 창은 miroe에서 네모(□)로, CrossOver 기반 엔진의 사용자 bottle에서는 빈칸으로 나왔어요. Mac의 Tahoma에는 한글이 없고, 글자가 없을 때 대신 쓸 글꼴 목록(`HKLM\…\FontLink\SystemLink`)은 Wine 기본값이 Windows 파일 이름(`GULIM.TTC`, `MALGUN.TTF` …)을 가리켜서 하나도 찾지 못했어요. Wine은 이 목록을 **파일 이름과 글꼴 이름이 둘 다 맞을 때만** 써요(`win32u/font.c`의 `load_system_links`). 그래서 글꼴 이름만 바꾸는 Replacements로는 해결되지 않았어요.

Miro(`CJKFonts.swift`)가 이제 자주 쓰는 UI 글꼴 13개(Tahoma, Segoe UI, Arial, Microsoft Sans Serif 등)에 Mac 자체 글꼴 파일을 연결해요. 순서는 한국어 `AppleSDGothicNeo.ttc`, 일본어 `ヒラギノ角ゴシック W3.ttc`(글꼴 이름은 `Hiragino Sans W3`여야 찾아요), 중국어 `Hiragino Sans GB.ttc`, 마지막으로 `Arial Unicode.ttf`예요. 글꼴 파일은 복사하거나 배포하지 않아요.

| 엔진 | 전 | 후 |
| --- | --- | --- |
| miroe | 네모 | 한국어 정상 ("Steam 업데이트 중…", "취소") |
| CrossOver 기반 | 네모 | 한국어 정상 |
| CrossOver 기반, 200% (Steam 설정) | — | 한국어 정상, 선명 |

한국어 입력(IME): miroe의 upstream Wine에는 한국어 입력 수정(MR 7701 `856efc7a95`, `WM_IME_KEYDOWN` 지원 `c0a81478f5`, 조합 메시지 순서 `af8f1b5fd0`, `NSTextInput` 전환 `6725f8d94f`)이 이미 들어 있어요. 실제 입력 확인은 화면 제어 허가가 필요해서 아직이에요.

## 9. miroe 단일 엔진 전환 (2026-11-28)

Miro는 이제 모든 게임과 Steam을 miroe 엔진에서 돌려요. 그래픽은 엔진이 자동으로 골라요(DirectX 10~12 Mullion, 1~9 WineD3D). 게임 설정과 앱 설정에서 엔진·그래픽 선택은 없앴어요. 예전 엔진(클래식, 최신)과 그 C: 드라이브는 지우지 않고 남겨 둬요.

### Steam 입력 확인 (miroe, 시험용 Steam)

| 확인 | 결과 |
| --- | --- |
| 클릭 (오버레이 패널 통과) | 됨. "로그인 정보 저장" 체크를 껐다 켬 |
| 영문 키 입력 | 됨 |
| 한글 조합 표시 (구름 입력기 2벌식) | 고치기 전: 조합 중인 글자가 안 보이고 완성돼야 들어감. 고친 뒤: ㄱ → 그 → 근이 바로 보임 |
| 받침 넘김, 백스페이스 | 근+ㅏ → 그 + 나, 나 → ㄴ → 지움 |

**원인**: Steam의 Chromium은 조합 중인 글자를 직접 그리지 않고 Windows 기본 입력기 창에 맡겨요(`WM_IME_COMPOSITION`을 `DefWindowProc`로 넘김). 그 창의 위치로 넘긴 값이 `CFS_RECT`에 빈 영역 (0,0)-(0,0)이어서, Wine의 기본 입력기 창(`imm32/ime.c`)이 1×1 크기로 화면 구석에 떴어요(TSF를 쓸 때는 창 아래쪽 바깥). CrossOver 기반 엔진도 증상이 같았어요.

**고친 방법** ([`patches/wine/0001`](../patches/wine/0001-imm32-Show-the-composition-where-the-text-field-is-w.patch)): 프로그램이 쓸 수 있는 위치를 주지 않으면, 그 스레드의 캐럿 위치, 없으면 입력칸을 클릭한 자리에 조합 창을 띄워요. 글꼴은 창의 DPI에 맞춘 크기예요. 창 크기도 실제 창 크기와 비교해서 맞춰요. Steam의 TSF를 끄는 설정은 필요 없었어요(끄지 않아도 같은 결과). 빌드 스크립트가 `patches/wine`을 자동으로 적용해요.

### 기본 글꼴: Noto Sans CJK KR

`NotoSansCJKkr-Regular.otf`, `-Bold.otf` (SIL OFL 1.1, notofonts/noto-cjk `f8d157532fbf`)를 엔진의 `miro/fonts`에 넣고, Miro가 각 prefix의 `C:\windows\Fonts`로 복제해요(APFS 복제라 공간을 더 쓰지 않음). 연결은 이렇게 해요.
- `FontSubstitutes`: `MS Shell Dlg`, `MS Shell Dlg 2` → Noto (Wine 대화상자 기본 글꼴)
- `Replacements`: 한국어·일본어·중국어 Windows 글꼴 이름, Segoe UI → Noto
- `SystemLink`: Tahoma 등 13개 글꼴의 첫 대체 글꼴 → Noto, 그다음 Mac 글꼴

| 시험 (`tests/engine2/fonttest.c`, `drawtest.c`) | 전 | 후 |
| --- | --- | --- |
| MS Shell Dlg / Malgun Gothic / 굴림 / Meiryo | Arial로 바뀜, 한글 없음, GDI+ 실패 | 그 이름 그대로, 한글·가나 있음, GDI+ 성공 |
| Tahoma로 "한글" 그리기 | — | 그려짐 (MS Shell Dlg와 같은 픽셀 수) |

Unity처럼 글꼴 파일을 직접 여는 게임이 `C:\windows\Fonts`에서 찾을 수 있게 파일도 그 폴더에 둬요. 게임 안의 글자가 안 보이던 문제(Sword Art Online: Integral Factor, miroe prefix에는 한글 글꼴 설정이 없었음)는 이 변경으로 고쳐졌을 가능성이 높지만, 사용자 게임은 실행하지 않아서 확인하지 못했어요.

### 화면 배율: Steam은 200 %, 게임은 예전처럼

Steam 창을 선명한 보통 크기로 보이려면 prefix 전체가 Retina + 192 DPI여야 해요(`-forcedesktopscaling 2`는 Windows판 Steam에서 효과 없음: 창이 절반 크기). Wine은 Retina와 DPI를 프로그램별로 나누지 않아요. 그래서 게임마다 `AppCompatFlags\Layers`에 `~ DPIUNAWARE`를 붙여요(Wine은 실행 파일 이름으로 찾음).

| 시험 (`dpitest.c`, Retina + 192 DPI) | DPI | 화면 크기 | 800×600 창 |
| --- | --- | --- | --- |
| 표시 없음 (DPI 모름 프로그램) | 96 | 1512×982 | 800×600 pt (2배로 그림) |
| 스스로 고해상도 요청 (Unity처럼) | 192 | 3024×1964 | — |
| 스스로 요청 + `~ DPIUNAWARE` | 96 (요청 거절됨) | 1512×982 | 800×600 pt |
| `~ HIGHDPIAWARE` | 192 | 3024×1964 | 400×300 pt |

게임 설정의 "Mac 원래 해상도로 실행"을 켜면 표시를 빼서 실제 픽셀로 그려요. 기본은 꺼짐이에요. Sword Art Online은 저장된 전체 화면 크기가 3024×1964(Retina 원본)였어요. 해상도 목록(`EnumDisplaySettings`)은 표시가 있어도 3024×1964로 나와서, 전체 화면 해상도를 고르는 게임은 직접 확인이 필요해요.

### 마이그레이션 (`MiroeMigration.swift`)

- Steam: miroe prefix의 `Program Files (x86)\Steam`을 예전 엔진(Miro-CX)의 Steam 폴더로 연결해요. 설치된 게임, 다운로드, Steam 설정이 그대로 쓰여요. 복사하지 않고, 링크를 지우면 원래대로예요.
- 세이브와 설정: 예전 prefix들의 `AppData\Local`, `LocalLow`, `Roaming`, `Documents`, `Saved Games`를 miroe 사용자 폴더로 APFS 복제해요. 이미 있는 것은 덮어쓰지 않고, 원본은 그대로 둬요. 복제한 목록은 prefix의 `.miro-migration.json`에 남겨요.
- Miro 라이브러리의 Steam 게임 경로는 링크 경로로 저절로 바뀌어요.

### Steam 화면과 동작

- 로그인은 Steam 창에서만 해요. Miro는 Steam 파일(`config/loginusers.vdf`, `config/avatarcache`)에서 계정 이름과 사진을 읽어요. 브라우저 로그인과 그 쿠키 저장소는 지웠어요.
- "라이브러리 미리보기": Steam이 라이브러리 그림을 둔 앱(`appcache/librarycache/<appid>`) 중 `appcache/appinfo.vdf`(v28/v29 바이너리)에서 종류가 game인 것. 사용자 Steam에서 146개.
- 버튼은 "Steam에서 보기"(`steam://nav/games/details/<appid>`, 스토어는 `steam://store/<appid>`)만 있어요. 다운로드와 실행은 Steam에서 해요.
- 다운로드가 끝난 게임만 Miro 라이브러리에 들어와요. 받는 중이고 한 번도 실행하지 않은 항목은 빠졌다가 끝나면 들어와요.
- "Steam 열기"는 사이드바에 항상 있어요. Steam이 없으면 눌러서 설치해요.
- Steam 게임을 누르면 Steam이 꺼져 있을 때 먼저 켜고, Steam 창 프로세스가 뜰 때까지(최대 4분) 기다린 뒤 `-applaunch`로 실행해요.
- Miro를 끄면 설정과 상관없이 Steam과 모든 Wine 프로세스를 끝내요.
- 로그 파일은 64MB에서 더 쓰지 않아요(예전에 한 게임 로그가 40GB가 됨).

### 실제 사용자 Steam으로 확인 (miroe, 2026-11-28)

| 확인 | 결과 |
| --- | --- |
| 예전 Steam 폴더 연결 + 설정 가져오기 | 저장된 계정으로 자동 로그인, 한국어 화면, 상점 페이지 그려짐 |
| 처음 실행 | Steam이 "Steam Service Error"를 메인 창 뒤에 띄움 → `steamservice.exe /install`로 해결, Miro가 Steam을 켤 때 자동으로 해요 |
| 엔진 파일을 바꾼 뒤 처음 실행 | Wine이 prefix를 업데이트하며 Wine Mono 설치 창을 띄움 → Miro가 먼저 조용히 업데이트해요 (`updateMiroePrefixIfNeeded`) |
| 라이브러리 미리보기 읽기 (앱 코드) | 282개 중 게임 146개, 3 ms |
| Miro 종료 | Steam을 포함한 Wine 프로세스 8개가 모두 꺼짐 |
| 세이브 복제 | 예전 prefix의 `Documents`는 Mac 문서 폴더로 가는 링크라서, 열면 macOS 폴더 접근 허가 창을 기다려 멈췄어요 → 링크는 건너뛰어요 |

아직 화면으로 확인하지 못한 것: Miro 사이드바와 라이브러리 미리보기 화면, Miro로 켠 Steam의 200 % 배율, 게임별 DPI 표시가 실제 게임에 주는 효과, 게임 안 글꼴.

### Steam 깜빡임과 업데이트 창 네모 글자 (2026-11-28)

**깜빡임** ([`patches/mullion/0004`](../patches/mullion/0004-winemetal-keep-the-panels-over-another-process-s-win.patch)): 사용자 Steam에서 측정했어요. Steam 창 하나에 Mullion 패널이 둘이었어요(메인 화면, 상점 내용). 둘 다 0.1초마다 "Steam 창 바로 위"로 자리를 옮기려 해서 계속 순서가 바뀌었어요(60번 중 45/15). 메뉴를 열면 더 심했어요. Wine은 메뉴 같은 자식 창을 부모 창 바로 위에 붙여 두는데, 패널이 그 사이에 끼면 다시 밀려나서 메뉴 패널이 메인 패널 밑으로 들어갔다 나왔다 했어요(80번 중 43/37). 이제 부모 창과 그 위에 붙은 같은 프로세스 창들을 한 묶음으로 보고, 묶음 맨 위에 패널을 창 순서대로 올려요. 패널이 없는 자식 창(Wine이 직접 그리는 대화상자)은 패널에 구멍을 내서 보이게 해요. 패널 위치는 1초에 60번 확인해요(전에는 10번).

| 확인 (사용자 Steam, miroe) | 전 | 후 |
| --- | --- | --- |
| 가만히 둘 때 창 순서 | 60번 중 45/15로 바뀜 | 100번 모두 같음 |
| 메뉴(라이브러리 호버)를 연 채 | 80번 중 43/37 (메뉴가 숨었다 나타남) | 80번 모두 같음, 메뉴가 맨 위 |
| 탭 이동 (라이브러리 ↔ 상점) | — | 정상, 순서 고정 |
| 화면 30장 연속 캡처 | — | 크기 변화 ±1 % (빈 프레임 없음) |
| 패널 확인에 드는 시간 | — | GPU 프로세스 샘플의 약 0.3 % |

남은 것: 메뉴가 처음 나타나는 순간 한 프레임 검게 보일 수 있어요(패널은 이제 투명이라 줄었지만 확인 전). 창을 끌 때 따라오는 지연은 16 ms 이하가 됐지만 측정하지 못했어요. 구멍 내기는 대화상자가 실제로 뜨는 상황에서 아직 확인하지 못했어요.

**업데이트 창 네모 글자**: miroe bottle의 글꼴 설정은 맞았어요(64비트·32비트 시험 프로그램 모두 Tahoma, MS Shell Dlg, 메시지 글꼴로 한글을 그림). 원인은 순서였어요. "Steam 열기"가 두 번 눌리자 두 번째 요청이 준비(글꼴, 200 %, prefix 업데이트)를 기다리지 않고 steam.exe를 바로 띄웠고, Steam이 13:10:39에, 글꼴 설정이 13:10:40에 끝났어요. 이제 준비 중에 온 요청은 기다렸다가 Steam이 뜬 뒤 넘겨요. 업데이트 창은 Steam이 업데이트할 때만 떠서 화면으로는 다시 확인하지 못했어요.

### 창을 끌 때 깜빡임, "steamwebhelper가 응답하지 않습니다" (2026-11-28 저녁)

**응답 없음 창**: 이 창을 띄운 건 두 번째 steam.exe였어요(창 주인 pid가 두 번째 Steam). Miro 로그 두 개가 1초 간격(`steam-1795856954.log`, `…955.log`)이었고, 두 번째 Steam은 Steam 자체 경고 `Steam3Master_SharedMemFile already existed - do we have two IPC servers with the same name?`를 남겼어요. 웹 화면 프로세스도 `-steampid=32`와 `-steampid=48` 두 벌이었는데, 두 번째 것은 끝내 뜨지 않았어요. "Steam 열기"를 두 번 누르면, 첫 Steam이 아직 뜨는 중이라 넘겨줄 곳이 없어서 두 번째 steam.exe가 Steam을 하나 더 띄웠어요. 이제 Miro는 Steam 웹 화면 프로세스가 뜬 뒤에만 두 번째 steam.exe를 띄우고(인자를 넘기고 바로 끝나요), 그 전에 온 요청은 기다렸다가 넘겨요(`SteamClient.start`, `handOverWhenUp`). 덧붙여, 켜고 2분 뒤 `--use-gl=disabled` GPU 프로세스가 한 번 뜨는 건 크롬이 GPU 정보를 모으는 정상 동작이에요(매 실행 2분째, 곧 끝남).

**창을 끌 때 깜빡임** ([`patches/mullion/0005`](../patches/mullion/0005-winemetal-show-another-process-s-window-through-Wine.patch)): 0004의 패널은 GPU 프로세스의 별도 창이라, 창을 끌면 1초에 60번 확인하며 뒤따라가요. 그동안 창 가장자리가 보였어요. 다른 프로젝트를 찾아봤어요.

| 프로젝트 | 방식 |
| --- | --- |
| Chromium (macOS) | GPU 프로세스가 CAContext로 레이어를 내보내고, 브라우저 프로세스가 CALayerHost로 창 안에 넣어요. 창 서버가 창의 일부로 그려서 따라갈 필요가 없어요 |
| Wine upstream (winemac.drv, 2026-05, Marc-Aurel Zent) | 같은 방식으로 다른 프로세스 창에 Vulkan·OpenGL을 그려요(`CAContextSwapChain`, `WM_MACDRV_CREATE_REMOTE_LAYER`). miroe의 Wine에 이미 들어 있어요 |
| Wine MR 11058 (메일링 리스트) | DXMT 같은 Metal 렌더러가 ExtEscape로 창의 Metal 레이어를 받는 제안이에요. miroe의 Wine에는 없어요 |
| Proton (`hack_append_command_line`) | 일부 CEF 런처에 `--in-process-gpu`, `--use-gl=swiftshader` 같은 옵션을 덧붙여요. steamwebhelper 항목은 없어요. Windows Steam 최신판에는 `-cef-in-process-gpu` 옵션도 없어요(`steamclient64.dll` 문자열 확인) |
| CrossOver·Whisky 사용자 글 | GPU 가속을 끄거나 Steam을 다시 켜는 우회책뿐이에요 |

그래서 Mullion이 Wine의 `CAContextSwapChain`을 그대로 불러 쓰게 했어요. 화면 레이어는 그 레이어 트리 안의 클라이언트 영역 자리에 들어가요. 레이어 좌표는 왼쪽 아래가 원점이에요. 처음엔 왼쪽 위로 계산해서 상점 화면이 탭 글자를 가렸고, 고쳤어요. 이 클래스가 없는 Wine에서는 예전 패널(0003/0004)을 그대로 써요.

| 확인 | 0004 (패널) | 0005 (CALayerHost) |
| --- | --- | --- |
| 창을 움직이는 동안(2 ms 간격 샘플) | 1029번 중 442번 패널이 창에서 어긋남, 최대 5 pt | GPU 프로세스 창 없음, 1041번 중 0번 |
| 시험용 Steam 로그인 창 | 정상 | 정상, 브라우저 창만 캡처해도 내용이 들어 있음 |
| 사용자 Steam: 상점·라이브러리 탭, 상점 메뉴(호버) | — | 제자리에 그려짐 |
| 크기 줄이기, 최소화 후 복원 | — | 창에 맞게 다시 그려짐 |
| 켜고 2분 뒤 GPU 정보 프로세스, 응답 없음 창 | 응답 없음 창 뜸(두 번째 Steam) | 뜨지 않음 |

창 이동은 Win32 `SetWindowPos`로 60단계 움직여 시험했어요(`tests/engine2/winctl.c glide`). 마우스로 직접 끄는 건 화면 조작 권한 요청에 응답이 없어서 못 해 봤지만, 그림이 창 안에 들어 있어서 창과 따로 움직일 수 없어요. Miro에서 "Steam 열기"를 빠르게 두 번 누르는 시험도 같은 이유로 아직 못 했어요.

**메뉴가 열릴 때 번쩍임** (Wine [`patches/wine/0002`](../patches/wine/0002-winemac-Show-nothing-of-a-window-another-process-dra.patch), Mullion `0005`): 상점·라이브러리·커뮤니티에 마우스를 올리면 메뉴 자리가 먼저 밝게 2프레임 보였어요(화면 녹화로 확인). 원인은 두 가지였어요.
- Wine은 새 창 바탕을 macOS 창 기본색(밝은 회색)으로 채우고 바로 화면에 올려요. Steam은 메뉴를 GPU로만 그리니까, 첫 프레임이 오기 전 이 바탕이 보였어요. 다시 열 때도 같았어요. Chromium은 메뉴를 열 때마다 스왑체인을 새로 만들고, 그건 창이 뜬 뒤예요.
- 이걸 막자 이번엔 검은 사각형이 2프레임 보였어요. Chromium이 열리는 메뉴에 처음 내보내는 프레임은 투명한 검정인데, Mullion 레이어가 불투명이라 검게 보였어요. Windows에서는 DirectComposition이 알파를 지켜서 안 보여요.

그래서 다른 프로세스가 그리는 창은 Wine 바탕을 내보이지 않고(앱이 직접 그린 게 생기면 다시 보여요), 첫 프레임 전까지 투명하게 두되 클릭은 창 전체에서 받아요. 그런 창에 그리는 Mullion 레이어는 알파를 지켜요. 녹화한 메뉴 여섯 번 열기(상점·라이브러리·커뮤니티 두 번씩)에서 흰 프레임도 검은 프레임도 없었고, 상점·라이브러리 화면에 뒤 창이 비치는 곳도 없었어요. 실제 마우스 클릭이 투명한 첫 프레임 동안 창에 들어가는지는 화면 조작 권한이 없어 직접 확인하지 못했어요.

## 10. 다른 Mac에 배포하기: Developer ID 서명 (2026-11-28)

**권한**: 개발용 프로필은 등록한 Mac에서만 돌아요. Developer ID용 프로필을 만들어 보니(App ID `app.miro.miroe`) `com.apple.developer.cross-architecture-support`가 들어 있고 `ProvisionsAllDevices`가 켜져 있었어요. 그래서 어느 Mac에서나 돌 수 있어요. Developer ID 인증서는 Xcode에서 만들 때 "Account Holder만 할 수 있어요" 오류가 나서, 웹사이트에서 CSR로 만들었어요.

**서명**: [`scripts/sign-engine-dist.sh`](../scripts/sign-engine-dist.sh)가 엔진의 Mach-O 파일 47개 모두를 Developer ID, 보안 실행 모드(hardened runtime), 시간 도장으로 서명해요. 공증에 필요한 조건이에요. 로더(`wine.app`)에는 배포용 프로필과 아래 예외 권한을 넣어요.

| 권한 | 왜 필요한가 |
| --- | --- |
| `allow-jit` | FEX가 x86 코드를 실행 중에 번역해요(MAP_JIT) |
| `allow-unsigned-executable-memory` | Windows 프로그램 코드는 Mach-O 서명이 없는 메모리에서 돌아요 |
| `disable-executable-page-protection` | CrossOver·Whisky와 같은 예외. 다만 이것만으로는 파일 매핑 메모리를 실행 가능으로 못 바꿔서 Wine 패치 0003이 필요했어요 |
| `allow-dyld-environment-variables` | Miro가 엔진의 FreeType·GnuTLS·MoltenVK를 `DYLD_FALLBACK_LIBRARY_PATH`로 알려줘요. `bin/wine`에도 넣어야 변수가 로더까지 가요 |

**보안 실행 모드에서 실행 메모리** (시험 프로그램, macOS 27.2): 익명 메모리 RW→RX는 돼요. 파일에서 매핑한 메모리(COW) RW→RX는 위 예외 권한이 다 있어도 `EACCES`예요. MAP_JIT은 돼요. Wine은 .exe/.dll을 파일 매핑으로 올려서 아무 프로그램도 시작하지 못했어요. 패치 [`wine/0003`](../patches/wine/0003-ntdll-Read-images-instead-of-mapping-them-under-the-.patch)는 보안 실행 모드일 때만 이미지를 읽어서 올려요(Wine이 이동식 디스크에서 하던 방식).

**시험** (`tests/engine2/dist-test.sh`, 새 bottle): Windows 환경 만들기(32비트 포함), HTTPS 3종, Vulkan 2종, D3D9 3종, D3D12, D3D11 게임 시험(ARM64, x86 32비트), FEX x86_64 메모리 시험, 13개 모두 통과했어요. 처음에는 HTTPS·Vulkan이 실패한 것처럼 보였는데, 시험 스크립트의 `/usr/bin/timeout`이 Apple 시스템 프로그램이라 `DYLD_*` 변수를 지워서였어요. Miro는 엔진을 바로 실행해서 해당 없어요.

**배포 파일**: `miroe-engine-1.2.0.tar.xz` 337MB(풀면 2.4GB, 빌드 도구·헤더·백업 제외). tar에 소유자 이름이 남지 않게 `--uid 0 --gid 0 --uname root --gname wheel`로 묶어요. Miro는 이 파일을 GitHub 릴리즈에서 받아 SHA-256을 확인하고 풀어요(`EngineManager.installMiroe`). macOS 27 아래나 Intel Mac에서는 받지 않고 이유를 보여줘요.
