# miroe

Miro의 차세대 엔진이에요. **애플 실리콘 Mac 전용 Wine 기반 엔진**으로, Wine 개발자들이 이미 알고 있는 문제를 Mac 고유 기술로 보완하는 게 목표예요. 연구 단계라서 Miro 앱에는 들어가 있지 않아요.

**지금 상태 (2026-11-27)**
- ARM64 Wine 11.22 + FEX + DXMT 연구 엔진을 빌드했어요(Hadron 기준, `scripts/`). Apple Developer 계정이 없어서 지금은 64비트 프로그램만 돌아요.
- 첫 연구 성과 **MUMA v0**: 큰 `WRITE_DISCARD` 몰아치기 뒤 남던 GPU 메모리 920MB가 312MB로 줄었어요. 속도는 그대로예요. 자세한 건 [RESEARCH.md](RESEARCH.md)에 있어요.

- [RESEARCH.md](RESEARCH.md): 통합 연구 엔진 계획 (합칠 프로젝트, 라이선스, 연구 과제 순위)
- [PROBLEMS.md](PROBLEMS.md): Mac용 Wine의 알려진 문제 목록과 miroe의 방향
- 측정 도구: [`tools/profile.sh`](tools/profile.sh)(CPU 시간), [`tools/frame-breakdown.py`](tools/frame-breakdown.py), [`tools/memwatch.sh`](tools/memwatch.sh)(메모리)
- 한중일 글꼴 연결: [`prefix/cjk-fonts.py`](prefix/cjk-fonts.py)
- 그래픽 다리: [`../miro-metal-bridge`](../miro-metal-bridge)
- 화면 없는 테스트: [`../tests`](../tests)

## 먼저 잰 것: CPU 시간은 어디에 쓰이나

화면 밖 D3D11 벤치마크(`Engine/tests/d3d11-bench.cs`의 `soak` 모드, 그리기 명령이 많은 장면)를 Instruments로 8초씩 기록했어요. 2026-11-27, M4 Pro, 엔진 두 개, DXMT.

| 어디서 | WineHQ 11.21 + Miro Metal Bridge | CrossOver 26.3 트리 Wine 11.0 |
| --- | ---: | ---: |
| macOS 프레임워크: Metal, GPU 드라이버 (Rosetta가 번역) | 52.6% | 45.8% |
| Windows 코드: 프로그램, DXMT의 Windows 쪽, .NET (Rosetta가 실행 중 번역) | 37.3% | 43.9% |
| Rosetta 자체 (번역, 분기 처리) | 9.4% | 9.9% |
| **Wine의 Unix 쪽** (ntdll.so, win32u.so, winemac.so) | **0.6%** | **0.4%** |

- **Wine 자체는 거의 시간을 쓰지 않아요.** Wine을 다시 짜도 이 장면은 빨라지지 않아요.
- **가장 큰 몫은 Metal과 GPU 드라이버예요.** Intel용 프로세스 안에서는 Apple의 Metal과 GPU 드라이버도 Intel용 코드로 돌고, Rosetta가 그걸 번역해요. DXMT가 그리기 명령을 Metal에 넘기는 스레드(`dxmt-encode-thr`)는 시간의 85%를 여기서 써요.
- 그래서 **엔진 프로세스를 ARM64로 네이티브 실행하고 게임의 Intel 코드만 번역하는 것**이 Rosetta 종료 대비이면서 가장 큰 성능 개선 후보예요. 그러면 Metal, GPU 드라이버, Wine, DXMT의 Mac 쪽은 번역 없이 돌아요.
- 주의할 점: 알려진 바로는 macOS에서 Intel식 메모리 순서(TSO)를 하드웨어로 켜는 건 Rosetta만 할 수 있어요. 그래서 FEX로 번역하는 게임 코드는 Rosetta보다 느릴 수 있어요. 둘을 합친 결과는 실제로 재 봐야 해요.

### 재는 방법

Rosetta가 번역한 프로세스에서는 Instruments가 원래 주소가 아니라 번역된 코드의 주소만 기록해요. 그래서 `profile.sh`는 같은 프로세스의 메모리 지도(`vmmap`)도 저장하고, `frame-breakdown.py`가 주소를 영역으로 나눠요.

- `<라이브러리>.aot`: Rosetta가 미리 번역한 Mac 라이브러리 (Wine, DXMT의 winemetal.so, MoltenVK)
- `Rosetta JIT`: 실행 중에 번역한 코드. Wine에서는 Windows 코드 전부예요.
- `/usr/libexec/rosetta/runtime`: Rosetta 자체
- 시스템 공유 캐시 범위 안의 빈 곳: 번역된 macOS 라이브러리와 프레임워크 (Metal, GPU 드라이버 포함)

```bash
Engine/miroe/tools/profile.sh <결과 폴더> <C: 드라이브> 8 -- <실행 스크립트> '{log}' bench.exe run <셰이더 폴더> soak 22
```

실행 스크립트는 프로그램을 시작하고 Wine 출력을 `{log}`에 써야 해요. 창이 화면에 뜨면 바로 끄는 스크립트를 쓰세요. 테스트에는 중립 테스트 프로그램만 써요.

## 첫 개선: 한중일 글꼴 (다운로드 없이)

새 C: 드라이브에서는 한국어가 네모(□)로 나와요. GDI에서는 한중일 전부 네모예요([Wine #60881](https://bugs.winehq.org/show_bug.cgi?id=60881)과 같은 원인). 지금 Miro는 Source Han Sans(약 120MB)를 받아서 고쳐요. `prefix/cjk-fonts.py`는 Windows 글꼴 이름을 **Mac에 이미 있는 글꼴**에 연결해서 다운로드 없이 고쳐요.

| C: 드라이브 | `Engine/tests/cjk-text-test.cs` 실패 (152개 중) |
| --- | ---: |
| 새 C: 드라이브 | 140 |
| + `cjk-fonts.py` | **8** (Segoe UI만. 글꼴이 없는 기본 Wine과 같아요) |

두 엔진(WineHQ 11.21, CrossOver 26.3 트리) 모두 같은 결과예요.

함께 찾은 것: Wine의 GDI는 Mac 글꼴을 모두 찾지만, **GDI+는 Apple SD 산돌고딕 Neo, 히라기노 명조, Songti, Heiti를 찾지 못해요**(`FontFamilyNotFound`). .NET·WinForms 프로그램은 GDI+가 글꼴을 못 찾으면 오류로 멈춰서, 지금은 GDI+가 찾는 글꼴(Arial Unicode MS, Hiragino Sans W3, Hiragino Sans GB W3)만 연결해요. GDI+를 고치면 한국어도 산돌고딕으로 바꿀 수 있어요.

## 목표 구조

| 층 | miroe |
| --- | --- |
| CPU | ARM64로 네이티브 실행 (ARM64EC Wine). 게임의 Intel 코드만 [FEX](https://github.com/FEX-Emu/FEX)(MIT)로 번역 |
| 그래픽 | DXMT + Miro Metal Bridge. Wine에 공식 Metal 통로가 생기면 갈아타기 |
| 동기화 | Mach 세마포어 기반 [msync](https://github.com/marzent/wine-msync)(LGPL-2.1) |
| 글꼴 | Mac 시스템 글꼴 연결, 이어서 GDI+ 수정 |
| 동영상·입력·오디오 | VideoToolbox, GameController, CoreAudio (PROBLEMS.md 6~9번) |
| 기반 | 공식 Wine 소스를 따라가고, 우리 패치는 작게 유지 |

## 다음 단계

1. **ARM64 빌드 준비**: Windows용 크로스 컴파일러 [llvm-mingw](https://github.com/mstorsjo/llvm-mingw)(macOS용 약 119MB), Wine 11.22 소스, FEX 소스가 필요해요.
2. **miroe 0.1**: ARM64EC Wine + FEX + DXMT를 직접 빌드하고, 같은 벤치마크로 지금 엔진과 비교해요.
3. **빠른 성과**: msync, GDI+ 글꼴, 컨트롤러 지연, 게임 모드 (PROBLEMS.md 3·6·7·10번)

## 주의

- C: 드라이브를 다른 엔진으로 처음 열면 Wine이 "업데이트 중" 창을 띄워요. 엔진을 바꿀 때는 먼저 화면 없이(`winemac.drv=d`) `wineboot -u`를 돌려요. Miro는 이미 이렇게 해요.
- 테스트에는 사용자 게임을 쓰지 않아요.
