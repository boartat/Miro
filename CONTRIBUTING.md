# 기여하기

고마워요! 저장소를 포크하고, 새 브랜치에서 고친 다음 Pull Request를 보내 주세요.

## 빌드

Xcode 16 이상, Apple 실리콘 Mac. 외부 라이브러리는 Swift Package Manager가 받아요.

```bash
xcodebuild -project Miro.xcodeproj -scheme Miro -configuration Release -derivedDataPath build build
```

## 코드 스타일

- 들여쓰기는 공백 4칸이에요. `.swiftlint.yml` 규칙을 따라 주세요.
- 화면 문구는 한국어로 써 주세요.
- 화면이 바뀌는 PR에는 스크린샷을 붙여 주세요.

## 스크린샷 (README용)

실제 게임 목록이 사진에 나오지 않도록, 가짜 데모 라이브러리로 Miro를 따로 띄워서 찍어요. 사용자 이름이 경로에 보이지 않게 `/Users/Shared` 아래에 만들어요.

```bash
swift Scripts/make_demo_library.swift /Users/Shared/MiroDemo
```

```bash
build/Build/Products/Release/Miro.app/Contents/MacOS/Miro -MiroLibraryFolder /Users/Shared/MiroDemo/Library
```

창을 `screencapture -o -l <창 번호>`로 찍어 한 폴더에 모은 다음, 배경과 그림자를 넣어요.

```bash
swift Scripts/frame_screenshots.swift <찍은 사진 폴더> docs/screenshots
```

## 라이선스

보내 주신 코드는 GPL-3.0 이상으로 배포돼요. 다른 프로젝트의 코드를 가져올 때는 GPL-3.0과 함께 쓸 수 있는 라이선스인지 확인하고 `THIRD_PARTY_NOTICES.md`에 적어 주세요. Apple D3DMetal 같은 바이너리는 저장소에 넣지 않아요.
