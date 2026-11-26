# miroe 연구 계획: 통합 연구 엔진

miroe는 이미 문제를 풀고 있는 오픈소스 프로젝트들의 결과를 합친 **연구용 통합 엔진**이에요. 그 위에서 아직 아무도 풀지 못한 고수준 문제를 연구해요.

- **기반(ARM64 Wine + FEX + DXMT)은 성과가 아니에요.** MetalSharp, Hadron이 이미 해 놓은 걸 라이선스를 지켜 가져와요. 직접 다시 만들지 않아요.
- **성과는 기반 위에서 측정한 실제 병목을 구조적으로 개선하는 것**이에요. 패치 개수보다 파급력과 검증 가능한 숫자를 우선해요.
- 어떤 기술도 "세계 최초"라고 하지 않아요. 독창성은 구체적인 구현과 측정 결과로 판단해요.

2026-11-27에 각 저장소, 이슈 본문, 기여 정책을 직접 확인했어요.

## 1. 합칠 프로젝트와 라이선스

| 프로젝트 | 가져올 것 | 라이선스 |
| --- | --- | --- |
| [Wine](https://gitlab.winehq.org/wine/wine) | 기반 소스 (커밋 고정) | LGPL-2.1+ |
| [FEX](https://github.com/FEX-Emu/FEX) | Intel 코드 번역 (ARM64EC) | MIT |
| [DXMT](https://github.com/3Shain/dxmt) | D3D10/11 → Metal | LGPL-2.1+ |
| [Hadron](https://github.com/Broyojo/hadron) | 소스 고정 방식(`sources.conf`)과 컴포넌트별 패치(`patches/wine, fex, dxmt …`), 빌드 스크립트 | 자체 코드 BSD, 패치는 각 컴포넌트 라이선스 |
| [MetalSharp Wine](https://github.com/metalsharp/MetalSharp-Wine) | Wine 변경(16K 페이지, TEB, JIT 메모리 보호, 시작 속도 등), FEX 포크, Mullion(DXMT 포크) | Wine 변경 LGPL-2.1+, FEX MIT, Mullion LGPL-2.1+. **스크립트·문서 등 자체 통합 코드는 AGPL-3.0이라 가져오지 않아요** |
| [WineForge](https://github.com/Alien4042x/WineForge) | macOS 수정, msync(USync) | LGPL-2.1+ |
| [mtld3d](https://github.com/athei/mtld3d) | D3D9 → Metal | zlib |
| Miro Metal Bridge (우리) | Intel용 공식 Wine에서 DXMT | LGPL-2.1+ |

**규칙**
- 가져온 패치마다 첫머리에 출처(프로젝트, 원래 작성자, 커밋, 라이선스)를 적어요.
- Miro는 GPL-3.0이라 LGPL, MIT, BSD, zlib 코드를 함께 배포할 수 있어요. AGPL 코드는 넣지 않아요.

## 2. 구조

Hadron 방식을 따라가요. 업스트림 소스는 커밋으로 고정하고, 우리 변경은 컴포넌트별 패치로만 둬요.

```
Engine/miroe/
  sources.conf          업스트림 저장소와 고정 커밋
  patches/<컴포넌트>/   NNNN-설명.patch (출처 머리말 포함)
  scripts/              fetch, build-wine, build-fex, build-dxmt, package
  tools/                profile.sh, memwatch.sh, frame-breakdown.py
  prefix/               C: 드라이브 설정 (cjk-fonts.py)
```

빌드와 실험은 **`/Users/Shared/miroe-lab`** 에서만 해요. 경로가 짧아야 Wine이 안전해요. Miro의 엔진과 C: 드라이브(사용자 데이터)는 건드리지 않아요.

## 3. 연구 과제

### 1순위: Apple Silicon 통합 메모리 관리 (MUMA, 가칭)

- **문제**: [DXMT #260](https://github.com/3Shain/dxmt/issues/260) (Open, PR 없음). Deadlock에서 큰 `WRITE_DISCARD` 업로드가 몰린 뒤 스테이징 블록 큐가 줄어들지 않아요. 작성자는 GPU 메모리가 1.5GB에서 7.2GB까지 늘었고, 자신의 수정으로 35분 동안 1.3~1.9GB를 유지했다고 보고했어요.
- **재현 (2026-11-27)**: `Engine/tests/d3d11-memory-test.cs`(중립 테스트, 화면 없음)와 `tools/memwatch.sh`로 실습실 DXMT v0.80에서 재현했어요. v0.80과 지금 main의 할당기 파일은 같아요.

  | | 유휴 GPU 메모리 |
  | --- | ---: |
  | 몰아치기 없음 (대조군) | 5MB |
  | 32MB보다 큰 discard 600프레임 뒤, 조용한 구간 3000프레임 | **920MB** (줄지 않음) |

- **연구 방향**: 작성자의 수정을 기준선으로 삼고, 그보다 나은 구조를 찾아요.
  - macOS 메모리 압력 알림에 따라 할당 정책 바꾸기
  - GPU 작업 완료 시점 기준 회수
  - 크기별 풀
  - 남는 블록을 Metal의 purgeable 상태로 두기
  - `MTLHeap`, `MTLResidencySet` 활용
  - 통합 메모리에서 복사 없는 업로드 경로
- **측정**: 같은 테스트로 최대치·유휴 메모리·프레임 시간을 비교해요. 게임별 패턴은 중립 테스트로 흉내 내요.

### 2순위: 그래픽 명령 처리 구조

- **문제**: [DXMT #204](https://github.com/3Shain/dxmt/issues/204) (Open). DEFAULT 상수 버퍼에 `UpdateSubresource`를 할 때 그 버퍼가 **픽셀 셰이더에 묶여 있으면** 비용이 그리기 횟수의 제곱으로 늘어요. 그리기 24,000번에서 DXMT 87.29ms, D3DMetal 12.17ms예요(같은 실행 파일, M3 Max). ARM64 + FEX에서도 같다고 보고돼 있어서 ARM64 전환으로는 해결되지 않아요.
- **연구 방향**: 먼저 관련 수정이 있는지 확인해요(이슈에 댓글이 없어서 아직 못 찾았어요). 그다음 픽셀 셰이더에서만 생기는 이유와 제곱이 되는 근본 원인(버퍼 버전 관리, 인자 버퍼 재인코딩)을 DXMT 소스와 Metal 쪽 측정으로 찾아요.

### 3순위: x86 ↔ ARM64 경계 최적화

ARM64 엔진을 만든 뒤 `tools/profile.sh`로 재요. 네이티브 프로세스라 Mac 쪽 기호가 보여서 지금보다 자세히 잴 수 있어요. 대상은 FEX 경계, Wine Unix 호출, Metal 호출에 남은 비용이에요.

### 4순위: 가상 메모리와 Metal

- **문제**: [DXMT #161](https://github.com/3Shain/dxmt/issues/161) (Open, DXMT 개발자 직접 등록). 32비트 프로세스는 DEP가 기본으로 꺼져 있어서 Wine이 메모리에 실행 권한을 주는데, Tahoe 이후 Metal이 그런 메모리를 아주 느리게 다뤄요. Metal HUD는 55~76 FPS인데 실제 `Present()`는 초당 약 5번이에요.
  - 피해 게임: Aokana, Mahjong Soul 등 32비트 Unity. **Miro 사용자층과 겹쳐요.**
  - 우회책: PE 헤더에 `NX_COMPAT`를 넣는 방식이 있어요.
- **연구 방향**: DXMT 개발자가 제시한 방향이에요. 프로세스 전체 DEP 정책을 바꾸지 않고, DXMT가 Wine을 통해 할당하는 placed buffer 메모리만 실행 불가로 만들어요. Wine의 32비트 주소 관리(WoW64)와 같이 봐야 해요.

### 5순위: 셰이더 컴파일

DXMT의 셰이더 변환기(airconv, LLVM 15)와 Metal 파이프라인 컴파일의 끊김을 재요. 캐시, 미리 컴파일, 백그라운드 컴파일을 연구해요.

### 6순위: 차등 호환성 분석

같은 중립 테스트를 여러 엔진(miroe, Highball, WineHQ + 다리)에서 자동으로 돌려서 차이를 표로 만들어요. 측정 도구와 테스트는 이미 있어요.

### 7순위: 적응형 실행

측정 결과를 Miro의 자동 실행 순서(LaunchPlanner)에 연결해요.

### 연구 과제가 아닌 것

| 이슈 | 이유 | 다룰 방식 |
| --- | --- | --- |
| [DXMT #230](https://github.com/3Shain/dxmt/issues/230) GPU 동기화 | DXMT 개발자가 #251로 고침 (재현 통과) | 회귀 테스트 |
| [DXMT #200](https://github.com/3Shain/dxmt/issues/200) GPU 장시간 정지 | 치명적 오류는 v0.80 이후 커밋 aadf0fb에서 고침 | 회귀 테스트 |
| 프로세스 간 그래픽 ([PR #166](https://github.com/3Shain/dxmt/pull/166), 2026-11-26 병합 없이 닫힘) | Wine 개발진이 새 GL/Vulkan 구조로 해결 중 | 업스트림 추적 |

## 4. 정책

- **DXMT에는 AI가 만든 코드를 PR로 내지 않아요.** DXMT의 [기여 정책](https://github.com/3Shain/dxmt/blob/main/CONTRIBUTING.md)은 AI/LLM이 만들었거나 같이 만든 기여를 받지 않아요. AI로 한 연구 결과와 재현 자료를 공유하는 건 허용해요(PR이 아닌 이슈·댓글로).
- 결과를 공유할 때는 짧고 확인 가능한 내용만 써요. DXMT 개발자는 AI가 덧붙인 장황한 "근거" 부분을 보고서를 읽기 어렵게 만드는 잡음이라고 했어요(#200).
- Wine에 코드를 넣으려면 실명이 필요해요. 하게 되면 그때 따로 정해요.
- 사용자 게임은 테스트에 쓰지 않아요. 중립 테스트 프로그램만 쓰고, 창은 화면 밖에 둬요.
- Miro의 기존 엔진과 사용자 데이터는 건드리지 않아요.

## 5. 다음 단계

1. **도구 설치와 소스 받기** (사용자 확인 필요)
   - Homebrew: `cmake`, `ninja`, `meson`, `pkg-config`
   - llvm-mingw(약 119MB)
   - 소스: Wine, FEX(+서브모듈), DXMT, LLVM 15(DXMT의 셰이더 변환기용), Hadron·MetalSharp 패치
2. **기준 엔진**: Hadron의 고정 커밋과 패치로 ARM64 Wine + FEX + DXMT를 빌드하고, 테스트·벤치마크·프로파일을 돌려요. DXMT는 v0.80이 아니라 최신 main을 써요(#200, #230 수정이 v0.80 이후예요).
3. **1순위 연구 시작**: DXMT를 직접 빌드해서 #260 작성자의 수정(기준선)을 재고, MUMA 설계를 시험해요.
4. MetalSharp의 Wine 패치 중 Hadron에 없는 것을 비교해서 더해요.
