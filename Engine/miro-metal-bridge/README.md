# Miro Metal Bridge

Miro가 직접 만든 변환층이에요. **공식 WineHQ Wine 11**에서 [DXMT](https://github.com/3Shain/dxmt)(DirectX 10/11 → Metal)가 게임 창에 그릴 수 있게 해 줘요. 원래 DXMT는 CrossOver 계열 Wine에서만 창에 그릴 수 있어요. Miro Metal Bridge는 Wine Mac 드라이버(`winemac.so`)만 바꾸고, 엔진의 나머지는 공식 빌드 그대로 둬요.

- **Miro 1.1**: 최신 엔진(WineHQ 11.21 Staging)에 들어가 DXMT를 켰어요.
- **Miro 1.2**: 기본 최신 엔진(CrossOver 26.3 트리 Wine 11)은 이 변환층 없이 DXMT를 쓸 수 있어서, 지금은 앱에 들어 있지 않아요.

## 성능

화면 밖 D3D11 벤치마크([`Engine/tests`](../tests), 그리기 명령 4000번 + 셰이더 전환, 1프레임당 ms, 낮을수록 좋음). M4 Pro, 구성마다 5번씩 번갈아 실행한 평균이에요.

| 구성 | 그리기 명령 부담 |
| --- | --- |
| WineHQ 11.21 + Miro Metal Bridge + DXMT v0.80 | **2.36** (2.31~2.42) |
| WineHQ 11.21 + Miro Metal Bridge + DXMT (Highball 빌드) | 2.42 (2.33~2.55) |
| CrossOver 26.3 트리 Wine 11.0 + DXMT (Highball 빌드), Miro 1.2 기본 | 2.61 (2.56~2.67) |
| CrossOver 26.3 트리 Wine 11.0 + DXMT v0.80 | 2.96 (2.93~3.00) |

무거운 셰이더(GPU 부담) 테스트는 모든 구성이 0.08ms 안팎으로 같았어요.

## 빌드

```bash
brew install bison
```

```bash
Engine/miro-metal-bridge/build.sh
```

Wine 11.21과 Wine Staging 11.21 소스를 받아 SHA-256을 확인하고, Staging 패치와 `miro-metal-bridge.patch`를 적용한 뒤 `winemac.so`만 빌드해요. Windows용 크로스 컴파일러는 필요 없어요.

## 라이선스

Wine과 이 패치는 LGPL-2.1 이상이에요. 이 소스로 빌드한 라이브러리를 넣었던 Miro 1.1.0 릴리즈에도 전체 소스가 첨부돼 있어요.
