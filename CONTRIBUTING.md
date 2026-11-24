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

## 라이선스

보내 주신 코드는 GPL-3.0 이상으로 배포돼요. 다른 프로젝트의 코드를 가져올 때는 GPL-3.0과 함께 쓸 수 있는 라이선스인지 확인하고 `THIRD_PARTY_NOTICES.md`에 적어 주세요. Apple D3DMetal 같은 바이너리는 저장소에 넣지 않아요.
