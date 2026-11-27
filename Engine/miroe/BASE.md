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
| D3D10/11/12 | **Mullion 채택을 검토** (LGPL, DXMT 포크, D3D12 FL 12_2). MUMA는 Mullion 위에 다시 맞춰요 | PROBLEMS.md D1. DXMT 본가와 Mullion 중 하나를 정하는 비교 측정이 필요해요 |
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
