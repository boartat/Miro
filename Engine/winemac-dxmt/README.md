# winemac-dxmt

최신 엔진(Wine 11.21 Staging)에서 [DXMT](https://github.com/3Shain/dxmt)를 쓰기 위한 Wine Mac 드라이버(`winemac.so`) 패치예요. Miro.app에 든 `Miro/Engine/winemac-11.21-dxmt.so.bin`이 이 소스로 빌드한 파일이에요. 최신 엔진에 DXMT를 설치할 때 원래 `winemac.so` 대신 들어가고, 원래 파일은 엔진의 `miro/original`에 보관돼요.

## 빌드

```bash
brew install bison
```

```bash
Engine/winemac-dxmt/build.sh
```

Wine 11.21과 Wine Staging 11.21 소스를 받아 SHA-256을 확인하고, Staging 패치와 `winemac-dxmt.patch`를 적용한 뒤 `winemac.so`만 빌드해요.

## 라이선스

Wine과 이 패치는 LGPL-2.1 이상이에요. 빌드한 라이브러리에 해당하는 전체 소스는 각 Miro 릴리즈에 첨부돼요.
