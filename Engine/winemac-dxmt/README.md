# winemac-dxmt

최신 엔진(Wine 11.21 Staging)에서 [DXMT](https://github.com/3Shain/dxmt)가 동작하도록 고친 Wine Mac 드라이버(`winemac.so`)의 소스예요. Miro.app에는 이걸로 빌드한 `Miro/Engine/winemac-11.21-dxmt.so.bin`(확장자만 바꾼 winemac.so)이 들어 있고, 최신 엔진에 DXMT를 설치할 때 원래 `winemac.so` 대신 들어가요. 원래 파일은 엔진의 `miro/original`에 보관돼요.

## 왜 필요한가

DXMT는 Direct3D 10/11을 Metal로 바로 그려요. 그러려면 Wine 창 안에 Metal 뷰를 만들어야 해서, Wine Mac 드라이버가 `macdrv_functions`라는 함수 표(CrossOver가 제공하는 인터페이스)를 공개해 주기를 기대해요.

공식 Wine은 이 표를 공개하지 않아요. 게다가 Wine 11부터는 DXMT가 읽는 창 정보 구조(`hwnd, cocoa_window, cocoa_view, client_cocoa_view`)도 달라졌어요. 그래서 함수만 공개하면 DXMT가 창 좌표를 뷰 포인터로 읽고 죽어요.

## 무엇을 바꿨나 (`winemac-dxmt.patch`)

- `dlls/winemac.drv/dxmt.c` (새 파일): DXMT가 기대하는 모양의 `macdrv_functions` 표를 공개해요.
  - `get_win_data()`는 Wine의 실제 창 정보를 넘기지 않아요. 대신 Wine의 Vulkan 경로와 똑같이 그 창에 "클라이언트 표면"을 만들고, 그 뷰를 DXMT가 읽는 자리에 넣은 작은 기록을 돌려줘요.
  - DXMT는 그 뷰 안에 Metal 뷰를 만들어요. Wine의 `MetalViewSwapChain`이 하는 것과 같은 방식이에요.
- `window.c`: 창이 움직이거나 크기가 바뀌면 DXMT 뷰도 따라가게 해요(`macdrv_dxmt_window_pos_changed`).
- `surface.c`: Wine이 GDI로 창을 다시 그릴 때 DXMT 뷰를 숨기지 않게 해요(`macdrv_dxmt_owns_view`).
- `macdrv.h`, `Makefile.in`: 위 함수 선언과 새 파일 추가.

DXMT를 쓰지 않는 게임에는 영향이 없어요. 공개 함수 표가 하나 늘어날 뿐이에요.

## 빌드

```bash
brew install bison
```

```bash
Engine/winemac-dxmt/build.sh
```

빌드 스크립트가 하는 일:
1. Wine 11.21과 Wine Staging 11.21 소스를 받고 SHA-256을 확인해요.
2. Staging 패치를 모두 적용한 뒤 이 패치를 적용해요. Gcenx 빌드와 같은 소스예요.
3. x86_64로 `winemac.so`만 빌드해서 `Miro/Engine/`에 넣어요.

Windows용(PE) 코드는 빌드하지 않아서 mingw가 필요 없어요. `pe-stub/clang`은 configure 검사만 통과시키는 빈 스크립트예요.

## 테스트

`Engine/tests/d3d11-smoke-test.cs`는 화면 밖 64×64 창에서 셰이더로 한 프레임을 그리고, 픽셀을 다시 읽어 PASS/FAIL을 출력해요. 화면에는 아무것도 뜨지 않아요. Wine 안의 .NET Framework `csc.exe`로 컴파일해요.

## 라이선스

Wine과 이 패치는 LGPL-2.1 이상이에요. 빌드한 라이브러리에 해당하는 전체 소스는 이 폴더와 위 업스트림 소스로 만들 수 있고, 각 Miro 릴리즈에도 첨부돼요.
