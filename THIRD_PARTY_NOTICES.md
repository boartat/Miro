# 오픈소스 고지 (Third-party notices)

## Miro

Miro는 [Whisky](https://github.com/Whisky-App/Whisky)(© Whisky contributors, GPL-3.0)를 고쳐서 만든 프로그램이고, 전체가 **GNU GPL 3.0 이상**(`LICENSE`)으로 배포돼요. 어떠한 보증도 없어요.

2026년에 Whisky에서 바꾼 내용: 앱 이름과 화면 전체(게임 라이브러리, 게임 페이지, 설정), 호환성 검사·로그 분석·라이브러리 설치 큐, 두 번째 Wine 엔진(Wine 11 CrossOver 26.3 트리 + DXMT / D3DMetal / DXVK)과 실행 순서 자동 선택, 런타임 설치기(Gcenx Game Porting Toolkit 빌드). 고친 Whisky 파일에는 머리말에 `Modified for Miro, 2026.`라고 적혀 있어요.

## Miro.app 안에 들어 있는 것

| 구성 요소 | 라이선스 | 소스 |
| --- | --- | --- |
| WhiskyKit, WhiskyThumbnail (Whisky) | GPL-3.0 | 이 저장소 |
| [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) 0.4.0 | Apache-2.0 (아래 전문) | GitHub |
| [cabextract](https://www.cabextract.org.uk/) 1.11 (libmspack 포함) | GPL-3.0 이상 (libmspack은 LGPL-2.1) | 각 릴리즈에 `cabextract-1.11.tar.gz` 첨부 (SHA-256 `b5546db1155e4c718ff3d4b278573604f30dd64c3c5bfd4657cd089b823a3ac6`) |
| 게임별 호환성 데이터 (`compat-db.json`, highball-db의 게임 항목에서 추림) | CC0-1.0 | [highball-db](https://github.com/gauthierpiarrette/highball-db) (`db/games`만 사용, ODbL인 `db/derived`는 쓰지 않음) |

Miro 1.1에는 Miro Metal Bridge, 곧 DXMT용으로 고친 Wine Mac 드라이버 `winemac.so`(LGPL-2.1 이상)가 들어 있었어요. 소스는 [Engine/miro-metal-bridge](Engine/miro-metal-bridge)와 1.1.0 릴리즈 첨부 파일에 있어요.

### miroe 엔진 (`Engine/miroe`; 엔진은 Miro.app 밖, 엔진 폴더에 따로 설치)

| 경로 | 출처와 라이선스 |
| --- | --- |
| `Engine/miroe/scripts` 일부 (`stage1.sh`, `stage2*.sh`, `build-wine.sh`) | [Hadron](https://github.com/Broyojo/hadron)의 스크립트를 가져오거나 고침. Copyright (c) 2026 David Andrews, BSD 3-Clause ([`LICENSE.hadron`](Engine/miroe/scripts/LICENSE.hadron)) |
| `Engine/miroe/patches/dxmt` | [DXMT](https://github.com/3Shain/dxmt) 위의 패치, LGPL-2.1 이상. MUMA v2(`0003`)는 [DXVK](https://github.com/doitsujin/dxvk)(zlib, Copyright (c) 2017 Philip Rebohle 외)의 메모리 정책(유휴 한도, 예산, 한 번에 푸는 양)을 참고했어요. DXVK 코드를 복사하지 않았어요 |
| `Engine/miroe/patches/mullion` | [Mullion](https://github.com/dttdrv/mullion)(DXMT 포크) 위의 패치, LGPL-2.1 이상. `0001`은 Hadron의 DXMT 패치를 그대로 쓴 거예요(Copyright (c) 2026 David Andrews, Hadron의 패치는 고치는 프로젝트의 라이선스를 따라요). `0005`는 엔진에 들어 있는 Wine winemac.drv의 `CAContextSwapChain`(Wine 커밋 `1a63b0d7c4`, Marc-Aurel Zent, LGPL-2.1 이상)을 불러 써요. 코드는 복사하지 않았어요. 같은 방식(CAContext + CALayerHost)은 Chromium(BSD 3-Clause)이 macOS에서 쓰는 방식이고, Chromium 코드도 가져오지 않았어요 |
| `Engine/miroe/patches/wine`, `Engine/miroe/patches/wine-x86_64` | [Wine](https://www.winehq.org) 위의 패치, LGPL-2.1 이상 |
| 엔진의 `miro/fonts` (설치 스크립트가 넣음, 저장소에는 없음) | [Noto Sans CJK](https://github.com/notofonts/noto-cjk) KR Regular·Bold, Copyright 2014-2021 Adobe (http://www.adobe.com/), SIL Open Font License 1.1. 라이선스 전문은 엔진의 `miro/licenses/noto-cjk-OFL.txt`. Miro가 각 C: 드라이브의 `windows\Fonts`에 복제해요 |
| `Engine/miroe/patches/experiments` | 비교용. DXMT #260 제보자가 글로 설명한 변경을 miroe가 구현한 것(코드 복사 없음), LGPL-2.1 이상 |
| 나머지 (`Engine/miroe`의 문서·도구·스크립트, `Engine/tests`) | Miro와 같은 GPL-3.0 이상 |

### miroe 엔진 배포 파일 (`miroe-engine-1.2.0.tar.xz`, 릴리즈 첨부)

Miro 1.2가 첫 실행 때 받는 엔진이에요. 라이선스 전문은 엔진 안의 `miro/licenses`에 들어 있어요. 고친 부분의 소스는 같은 릴리즈에 첨부해요. 고치지 않은 라이브러리는 아래 버전의 공식 소스로 Homebrew가 빌드한 그대로예요.

| 구성 요소 | 버전 | 라이선스 | 소스 |
| --- | --- | --- | --- |
| Wine | 11.22-280-gecca8e7552 + `Engine/miroe/patches/wine` 0001–0003 | LGPL-2.1 이상 | 릴리즈의 `wine-miroe-1.2.0-src.tar.xz` |
| Mullion | 0f22b2c + `Engine/miroe/patches/mullion` 0001–0005 | LGPL-2.1 이상 | 릴리즈의 `mullion-miroe-1.2.0-src.tar.xz` |
| FEX | 4f9c1f1e + Hadron의 macOS 패치 7개 | MIT | [FEX-Emu/FEX](https://github.com/FEX-Emu/FEX), [Hadron](https://github.com/Broyojo/hadron) |
| MoltenVK | 1.4.2 | Apache-2.0 | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK) |
| FreeType | 2.15.0 | FreeType License | [freetype.org](https://freetype.org) |
| GnuTLS | 3.8.14 | LGPL-2.1 이상 | [gnutls.org](https://www.gnutls.org) |
| Nettle | 4.0 | LGPL-3.0 이상 또는 GPL-2.0 이상 | [Nettle](https://www.lysator.liu.se/~nisse/nettle/) |
| GMP | 6.3.0 | LGPL-3.0 이상 또는 GPL-2.0 이상 | [gmplib.org](https://gmplib.org) |
| libidn2 | 2.3.8 | LGPL-3.0 이상 또는 GPL-2.0 이상 | [GNU libidn](https://www.gnu.org/software/libidn/) |
| libunistring | 1.5 | LGPL-3.0 이상 또는 GPL-2.0 이상 | [GNU libunistring](https://www.gnu.org/software/libunistring/) |
| libtasn1 | 4.21.0 | LGPL-2.1 이상 | [GNU libtasn1](https://www.gnu.org/software/libtasn1/) |
| gettext (libintl) | 1.0 | LGPL-2.1 이상 | [GNU gettext](https://www.gnu.org/software/gettext/) |
| p11-kit | 0.26.6 | BSD-3-Clause | [p11-glue/p11-kit](https://github.com/p11-glue/p11-kit) |
| libpng | 1.6.59 | libpng License | [libpng.org](http://www.libpng.org/pub/png/libpng.html) |
| Brotli | 1.2.1 | MIT | [google/brotli](https://github.com/google/brotli) |
| Noto Sans CJK KR | `sources.conf`의 noto-cjk | SIL OFL 1.1 | [notofonts/noto-cjk](https://github.com/notofonts/noto-cjk) |

`Engine/tests/c/sm6`의 셰이더는 Microsoft [DXC](https://github.com/microsoft/DirectXShaderCompiler)(LLVM 라이선스 + Microsoft 라이선스)로 컴파일해요. DXC와 컴파일된 셰이더는 저장소에 들어 있지 않아요.

## 앱이 처음 실행할 때 원래 배포처에서 내려받는 것 (Miro에는 들어 있지 않음)

| 구성 요소 | 라이선스 | 받는 곳 |
| --- | --- | --- |
| Game Porting Toolkit 빌드 (Wine 7.7 + Apple D3DMetal) | Wine: LGPL-2.1 · D3DMetal: Apple 라이선스 (비상업적 배포만 허용, 수정 금지) | [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit) |
| Wine 11 (CodeWeavers CrossOver 26.3 오픈소스 트리, Highball 빌드) | LGPL-2.1 이상 | [gauthierpiarrette/highball-engine](https://github.com/gauthierpiarrette/highball-engine) (빌드 레시피·패치), [CrossOver 소스](https://www.codeweavers.com/crossover/source) |
| 런타임 프레임워크 (GStreamer, FreeType, SDL2, MoltenVK … + Apple D3DMetal 3.0) | 각 라이선스 (LGPL, Apache-2.0, MIT …) / Apple 라이선스 | [Sikarugir-App/Template](https://github.com/Sikarugir-App/Template) |
| MoltenVK 1.4.2 (Highball 패치) | Apache-2.0 | [gauthierpiarrette/highball](https://github.com/gauthierpiarrette/highball) |
| 오디오 보정 라이브러리(audiobuf), 32비트 NVAPI 스텁 | MIT | [gauthierpiarrette/highball-engine](https://github.com/gauthierpiarrette/highball-engine) |
| DXVK-macOS 1.10.3 | zlib | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) |
| DXMT (Highball 브랜치, d3d11 · dxgi · d3d10core · winemetal) | LGPL-2.1 이상 (DXMT는 2026-04-25에 MIT에서 바꿨어요. Miro 1.1에 넣은 v0.80은 MIT) | [gauthierpiarrette/highball-engine](https://github.com/gauthierpiarrette/highball-engine), 원본 [3Shain/dxmt](https://github.com/3Shain/dxmt) |
| winetricks | LGPL-2.1 | [Winetricks/winetricks](https://github.com/Winetricks/winetricks) |
| Visual C++, DirectX, .NET, 글꼴 등 Windows 라이브러리 | 각 배포사(대부분 Microsoft)의 라이선스 | Miro에 들어 있지 않아요. winetricks(버전 고정, 해시 확인)가 배포사 서버(옛 DirectX 런타임은 원본과 해시가 같은 보관본)에서 받아 SHA-256으로 확인해요 |
| RPG Maker RTP | 각 RTP의 라이선스 | [rpgmakerweb.com](https://www.rpgmakerweb.com/run-time-package) |
| 게임 커버 이미지 | 각 게임 저작권자 | Steam 상점 (화면 표시용으로만 사용) |

Apple D3DMetal 라이선스 때문에 Miro는 **무료로만** 배포해요. 유료로 팔거나 D3DMetal을 고쳐서 넣으면 안 돼요.

## 소스에서 빌드할 때만 쓰는 것 (Miro.app에는 들어 있지 않음)

`WhiskyCmd` 명령줄 도구가 쓰는 라이브러리예요.

| 구성 요소 | 라이선스 |
| --- | --- |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 + Runtime Library Exception |
| [Progress.swift](https://github.com/jkandzi/Progress.swift) | MIT (아래 전문) |
| [SwiftyTextTable](https://github.com/scottrhoyt/SwiftyTextTable) | MIT (아래 전문) |

---

## 라이선스 전문

GPL-3.0 전문은 [`LICENSE`](LICENSE)에 있어요.

### SemanticVersion (Apache-2.0)

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

```

### swift-argument-parser (Apache-2.0 + Runtime Library Exception)

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

    TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

    1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

    2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

    3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

    4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

    5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

    6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

    7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

    8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

    9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

    END OF TERMS AND CONDITIONS

    APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

    Copyright [yyyy] [name of copyright owner]

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.


## Runtime Library Exception to the Apache 2.0 License: ##

    As an exception, if you use this Software to compile your source code and
    portions of this Software are embedded into the binary product as a result,
    you may redistribute such product without providing attribution as would
    otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.

```

### Progress.swift (MIT)

```text
The MIT License (MIT)

Copyright (c) 2015 Justus Kandzi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

### SwiftyTextTable (MIT)

```text
The MIT License (MIT)

Copyright (c) 2016 Scott Hoyt

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```
