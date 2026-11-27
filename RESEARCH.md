# miroe 연구 요약

**miroe**는 Miro의 차세대 엔진이에요. 애플 실리콘 하나만 지원하는 대신, Mac용 Wine에 남은 병목을 재고 고치는 데 집중해요. 이미 있는 오픈소스는 가져오고(출처 표기), 아무도 못 푼 부분만 직접 연구해요. [Claude](https://claude.ai)(AI)와 함께 연구하고 있고, 코드와 측정 결과는 모두 공개해요.

> 숫자는 모두 M4 Pro, macOS 27에서 직접 만든 **중립 테스트 프로그램**으로 잰 거예요. 실제 게임에서는 다를 수 있어요.

## 엔진 구성

| 층 | 선택 |
| --- | --- |
| Wine | 최신 upstream Wine, ARM64 macOS 지원 (MR !12716, macOS 27, 4K 페이지) |
| x86 번역 | [FEX](https://github.com/FEX-Emu/FEX) (+ [Hadron](https://github.com/Broyojo/hadron)의 macOS 패치) |
| D3D10/11/12 | [Mullion](https://github.com/dttdrv/mullion) (DXMT 포크) + miroe 패치 |
| 대조군 | 기존 x86_64 엔진 (Rosetta). 비교용으로만 써요 |

## 성과

### 1. MUMA: 돌아오지 않던 그래픽 메모리 ([DXMT #260](https://github.com/3Shain/dxmt/issues/260))

- **문제**: 게임이 버퍼를 자주 갈아 쓰면(`WRITE_DISCARD`), 쓰고 남은 블록이 프로세스가 끝날 때까지 남아요.
- **해결**: 명령 큐마다 회수 스레드를 둬서 GPU가 다 쓴 블록을 2초 뒤 풀고, 쉬는 블록은 purgeable로 표시해요. 메모리 한도와 예산 정책은 [DXVK](https://github.com/doitsujin/dxvk)를 참고했어요.

| GPU 메모리 | 원래 | MUMA | 줄어든 양 |
| --- | ---: | ---: | ---: |
| 동적 버퍼 몰아치기 뒤 | 920MB | 308MB | **−67%** |
| 렌더링을 멈춘 앱 | 920MB | 308MB | **−67%** |
| 동적 텍스처 | 968MB | 196MB | **−80%** |
| 게임형 테스트, 교전 뒤 | — | — | **−48~59%** |

속도와 프레임 시간은 그대로예요. DXMT와 Mullion 둘 다에 적용했고, 결과가 같아요.
패치: [`patches/dxmt`](Engine/miroe/patches/dxmt), [`patches/mullion`](Engine/miroe/patches/mullion)

### 2. Mullion에 옮기면서 찾은 충돌

Mullion은 GPU가 쉬는 동안 메모리를 상주시키는 "하트비트"가 있어요. 이게 purgeable 블록까지 붙잡아서 purgeable 효과가 **0**이 돼요(923MB). purgeable인 동안 하트비트에서 빼서 **308MB**로 고쳤어요.

### 3. W1: 32비트 게임 슬라이드쇼 ([DXMT #161](https://github.com/3Shain/dxmt/issues/161), Intel Wine + Rosetta)

- **원인** (Wine 없이 분리): Rosetta에서 쓰기+실행 메모리 위의 Metal 버퍼는 GPU가 쓴 뒤 CPU가 약 **1.2초** 멈춰요. DEP가 꺼진 32비트 프로그램은 Wine이 모든 메모리에 실행 권한을 붙여서 매번 걸려요.
- **해결**: 실제로 코드가 실행되는 페이지에만 실행 권한을 주는 Wine 패치.
- **결과**: 같은 시간에 **35 → 1,997프레임 (57배)**. 코드 실행 9가지 경우는 모두 그대로 동작해요.
- ARM64 엔진은 W^X 때문에 이 조건이 생기지 않아서, Rosetta 연구 성과로만 보존해요. 패치: [`patches/wine-x86_64`](Engine/miroe/patches/wine-x86_64)

### 4. D3DMetal 없이 DirectX 12 (ARM64 + Mullion)

| 확인 | 결과 |
| --- | --- |
| 기능 수준 / 셰이더 모델 | **12_2 / 6.7** |
| SM 5.0 그리기·텍스처·컴퓨트 | 모두 정확 |
| SM 6.0~6.6 (웨이브 연산, 16비트, 디스크립터 힙 직접 접근) | 모두 정확 |

닫힌 소스인 Apple D3DMetal에 기대지 않는 오픈소스 DirectX 12 경로예요. 아직 확인 안 한 것: 메시 셰이더, 레이 트레이싱.

### 5. 그 밖의 측정

- **한중일 글꼴**: 다운로드 없이 Mac 글꼴을 연결해서 글자 깨짐 **140 → 8개 (−94%)**.
- **Rosetta에서 시간이 어디에 쓰이나**: Wine 자체는 **1% 미만**, Rosetta가 번역한 Metal·GPU 드라이버가 **46~53%**. ARM64 네이티브로 가는 이유예요.

## 다음

1. 개발자 계정 서명이 생기면 upstream ARM64 Wine에 FEX + Mullion + MUMA를 올려서 같은 테스트를 다시 돌려요.
2. 동기화 비용: 이벤트·세마포어마다 wineserver를 왕복해요(Unity 게임 스레드 시간의 55%, [Hadron #148](https://github.com/Broyojo/hadron/issues/148)). 이미 있는 msync 계열을 가져와 재요.
3. 하드웨어 TSO, 메시 셰이더·레이 트레이싱 확인, 실제 메모리 압력 아래 MUMA 동작.

## 원칙

- 기존 오픈소스를 최대한 쓰고 출처를 밝혀요. AGPL 코드는 넣지 않아요. 패치는 고치는 프로젝트와 같은 라이선스(LGPL-2.1 이상)예요.
- 사용자 게임은 테스트에 쓰지 않아요. 측정은 중립 테스트 프로그램으로만 해요.
- DXMT는 AI가 만든 기여를 받지 않아서 PR을 내지 않아요.

## 자세한 자료

- [연구 기록 (측정표 전부)](Engine/miroe/docs/research-log.md)
- [기반 구성 검토 (upstream Wine vs Hadron, Mullion 검증)](Engine/miroe/docs/base.md)
- [문제 목록과 선행 기술 조사 (17개 프로젝트)](Engine/miroe/docs/problems.md)
- 테스트 프로그램: [`Engine/tests/c`](Engine/tests/c), 측정 스크립트: [`Engine/miroe/scripts`](Engine/miroe/scripts)
