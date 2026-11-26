# miroe: Mac용 Wine의 알려진 문제와 miroe의 방향

miroe는 Miro의 차세대 엔진이에요. **애플 실리콘 Mac 전용**으로, Wine 개발자와 Mac Wine 프로젝트들이 이미 알고 있는 문제를 모아서 그 약한 부분을 Mac 고유 기술로 보완하는 게 목표예요.

측정 결과와 첫 개선은 [README.md](README.md)에 있어요. 이 문서는 2026-11-26에 모은 자료예요.
- [Wine 버그 트래커](https://bugs.winehq.org)에서 운영체제가 macOS인 열린 버그 전부(604건)
- Mac Wine 프로젝트의 이슈: [Highball](https://github.com/gauthierpiarrette/highball/issues), [Gcenx macOS 빌드](https://github.com/Gcenx/macOS_Wine_builds/issues)
- Wine 개발자 논의: [MR 11058](https://gitlab.winehq.org/wine/wine/-/merge_requests/11058), [MR 11257](https://gitlab.winehq.org/wine/wine/-/merge_requests/11257), [DXMT PR 166](https://github.com/3Shain/dxmt/pull/166)

## 한눈에 보기

Wine 버그 트래커의 macOS 열린 버그 604건을 제목으로 나눴어요(대략적인 분류예요).

| 분야 | 건수 |
| --- | ---: |
| 특정 앱·게임의 충돌 (원인 미분류) | 288 |
| 그래픽 (D3D, OpenGL, Vulkan) | 66 |
| 입력 (마우스, 키보드, 컨트롤러, IME) | 53 |
| wineserver·ntdll·스레드·동기화 | 51 |
| .NET·설치 프로그램 | 44 |
| 글꼴·문자 (한중일 포함) | 21 |
| 오디오 | 19 |
| 다른 프로세스의 자식 창·런처 (CEF) | 16 |
| 동영상·코덱 | 14 |
| 전체 화면·창 순서·해상도·Retina | 11 |
| ARM64·16K 페이지·Rosetta | 11 |
| 네트워크 | 10 |

## 문제 목록

각 항목은 **문제 → 근거 → 지금 상황 → miroe의 방향** 순서예요. 난이도는 상(몇 달 이상), 중(몇 주), 하(며칠)예요.

### 1. CPU 번역: Rosetta가 끝나 가요 (난이도 상, 필수)

- **문제**: Windows 게임 코드는 Intel용이라 지금은 Rosetta 2가 번역해요. Apple은 macOS 27까지만 Rosetta를 온전히 지원하고, macOS 28(2027)부터는 일부 오래된 게임용으로만 남긴다고 했어요. Rosetta의 x87(옛 부동소수점) 처리도 느려요.
- **근거**: Wine on AArch64가 macOS에서 실행 안 됨 [#58567](https://bugs.winehq.org/show_bug.cgi?id=58567), 호스트 페이지 정렬 변경이 Rosetta에서 Wine을 깨뜨림 [#58084](https://bugs.winehq.org/show_bug.cgi?id=58084), x87 가속 프로젝트 [rosettax87](https://github.com/Lifeisawful/rosettax87)
- **지금 상황**: [MetalSharp Wine](https://github.com/metalsharp/MetalSharp-Wine)(ARM64/ARM64EC Wine + FEX), CrossOver ARM 빌드, Ferry, MacLauncher가 FEX로 가고 있어요.
- **miroe**: 엔진 자체는 ARM64로 네이티브 실행하고, 게임의 Intel 코드만 FEX로 번역해요. 전환기에는 Rosetta 경로를 예비로 둬요.
- **측정 (2026-11-27)**: 그리기 명령이 많은 D3D11 장면에서 CPU 시간의 46~53%가 Rosetta가 번역한 Metal·GPU 드라이버였고, Wine의 Unix 쪽은 1% 미만이었어요. ARM64 네이티브 실행이 가장 큰 개선 후보예요.

### 2. ARM64 Mac의 16K 메모리 페이지 (난이도 상)

- **문제**: Windows는 4K 단위로 메모리를 다루는데, 애플 실리콘 macOS는 16K 단위예요. ARM64로 직접 돌면 메모리 보호, 스택 가드 페이지, 정렬이 어긋나요.
- **근거**: 16K 페이지에서 4K 해제가 안 맞음 [#60572](https://bugs.winehq.org/show_bug.cgi?id=60572), 스레드 스택 가드 페이지 처리 [#60571](https://bugs.winehq.org/show_bug.cgi?id=60571), ARM64EC 64K 섹션 정렬 [#60570](https://bugs.winehq.org/show_bug.cgi?id=60570), ARM64EC 메모리 순서 [#60568](https://bugs.winehq.org/show_bug.cgi?id=60568) · [#60569](https://bugs.winehq.org/show_bug.cgi?id=60569), macOS에서 CPU 기능 조회가 비어 있음 [#60573](https://bugs.winehq.org/show_bug.cgi?id=60573), macOS에서 페이지 경계 접근 오류를 %gs 오류로 잘못 판단 [#60543](https://bugs.winehq.org/show_bug.cgi?id=60543)
- **지금 상황**: 버그는 열려 있고, 주로 ARM64 Wine을 만드는 사람들이 보고 중이에요.
- **miroe**: 4K 동작을 검증하는 화면 없는 테스트를 먼저 만들고, 고친 것은 Wine에도 돌려줘요.

### 3. 동기화와 wineserver 왕복 (난이도 중)

- **문제**: Windows의 잠금·이벤트를 Wine은 별도 프로세스(wineserver)를 거쳐 처리해요. Linux는 커널 기능(ntsync)으로 이 왕복을 줄이는데, macOS에는 그런 커널 기능이 없어요. 공식 Wine의 Mac 빌드에는 빠른 동기화가 없어요. Mach 세마포어를 쓰는 [msync](https://github.com/marzent/wine-msync)(LGPL-2.1, MR 11058을 쓴 mzent가 만들었어요)가 있지만, Highball 같은 CrossOver 계열 엔진에만 들어 있어요. 필요 없이 CPU를 계속 쓰는 대기 루프도 보고돼 있어요.
- **근거**: 스레드 풀 타이머가 할 일 없이 계속 돎 [#60694](https://bugs.winehq.org/show_bug.cgi?id=60694), CoreAudio 타이머 스레드가 바쁘게 기다림 [Gcenx #157](https://github.com/Gcenx/macOS_Wine_builds/issues/157)
- **miroe**: msync를 기본으로 넣어요(LGPL이라 가져다 쓸 수 있어요). 바쁜 대기 루프는 측정해서 없애요. 우리 벤치마크로 전후를 비교해요.

### 4. Metal 연결과 창 그리기 (난이도 중~상)

- **문제**: DXMT 같은 Metal 기반 그래픽이 Wine 창에 그리는 공식 통로가 없어요. Wine 창 구조가 바뀌면서 창 이동과 GDI 그리기 사이의 처리도 불안정해요.
- **근거**: `macdrv_surface_flush`와 `macdrv_WindowPosChanged`의 교착(언리얼 게임) [#60493](https://bugs.winehq.org/show_bug.cgi?id=60493), OpenGL 3.2+ 컨텍스트 생성 실패 [#60492](https://bugs.winehq.org/show_bug.cgi?id=60492), Unity 6이 D3D11 펜스에서 충돌 [#60300](https://bugs.winehq.org/show_bug.cgi?id=60300), DXGI 디스플레이 모드 목록이 일부만 구현됨 [#60222](https://bugs.winehq.org/show_bug.cgi?id=60222)
- **지금 상황**: Wine은 새 프로세스 간 GL 구조가 끝나면 winevulkan 안에 공식 Metal 통로를 만들 계획이에요(DXMT PR 166에서 mzent의 답).
- **miroe**: 그때까지는 Miro Metal Bridge를 써요. 공식 통로가 생기면 갈아타요. 교착(#60493) 같은 창 처리 버그는 다리와 같은 코드 근처라 우리 테스트로 재현해 볼 가치가 있어요.

### 5. 다른 프로세스의 자식 창: 런처가 까맣게 나와요 (난이도 상)

- **문제**: Steam, EA app 같은 런처는 웹 화면(CEF)을 다른 프로세스에서 그려서 창 안에 붙여요. Mac 드라이버는 이걸 제대로 못 보여 줘요.
- **근거**: 다른 프로세스 자식 창이 안 보임 [#35456](https://bugs.winehq.org/show_bug.cgi?id=35456), 프로세스 간 Metal 스왑체인 미구현(Steam이 까맣게 나옴) [#60263](https://bugs.winehq.org/show_bug.cgi?id=60263), GDI 자식 창이 OpenGL 창 뒤에 숨음 [#60578](https://bugs.winehq.org/show_bug.cgi?id=60578), EA app 화면이 하얗게 나옴 [#60282](https://bugs.winehq.org/show_bug.cgi?id=60282), [Gcenx #170](https://github.com/Gcenx/macOS_Wine_builds/issues/170)
- **지금 상황**: Wine 개발진의 합성(compositing) 개편이 이 문제를 겨냥하고 있어요.
- **miroe**: 직접 풀기보다 공식 개편을 따라가요. 그 사이에는 런처별 우회 설정(CEF 옵션)을 써요.

### 6. 전체 화면, 창 순서, 해상도, 게임 모드 (난이도 중)

- **문제**: macOS는 Windows처럼 해상도를 바꾸지 않아서 Wine이 흉내 내는데, 그 과정에서 화면이 확대되거나 창 순서가 틀어져요. Wine 프로세스는 앱 번들이 아니라서 macOS 게임 모드도 안 켜져요.
- **근거**: 전체 화면 창 위의 창이 뒤에 그려짐 [#60266](https://bugs.winehq.org/show_bug.cgi?id=60266), 해상도 흉내 모드에서 화면 일부가 확대됨 [#60736](https://bugs.winehq.org/show_bug.cgi?id=60736), 해상도가 바뀌면 Retina가 꺼짐 [#42973](https://bugs.winehq.org/show_bug.cgi?id=42973), DPI 비율 계산 중 중단 [#60798](https://bugs.winehq.org/show_bug.cgi?id=60798), Unity 게임이 앞으로 안 나옴 [#51194](https://bugs.winehq.org/show_bug.cgi?id=51194), 게임 모드 [Highball #338](https://github.com/gauthierpiarrette/highball/issues/338)
- **miroe**: Mac식 전체 화면(Space)과 해상도 흉내를 Metal 스케일링으로 처리하고, 게임 카테고리로 표시된 로더로 게임 모드를 켜요. Miro가 이미 가진 노치 전체 화면·Retina 설정을 엔진 안으로 옮겨요.

### 7. 입력: 컨트롤러 지연, 키, 커서 (난이도 하~중)

- **문제**: 컨트롤러 입력이 쌓이기만 하고 버려지지 않아 지연이 점점 커져요. 일부 키 조합과 커서 숨김도 어긋나요.
- **근거**: HID 입력 큐가 오래된 보고를 버리지 않아 컨트롤러 지연이 커짐 [#60522](https://bugs.winehq.org/show_bug.cgi?id=60522), 커서 숨김이 다음 메시지 때까지 늦어짐 [#60510](https://bugs.winehq.org/show_bug.cgi?id=60510), 오른쪽 Shift가 왼쪽으로 인식됨 [#44382](https://bugs.winehq.org/show_bug.cgi?id=44382), Ctrl+숫자가 숫자로 입력됨 [#53243](https://bugs.winehq.org/show_bug.cgi?id=53243), 제조사 전용 USB 장치 무시 [#60641](https://bugs.winehq.org/show_bug.cgi?id=60641)
- **miroe**: 컨트롤러는 Apple GameController 프레임워크로 직접 받아요. 입력 지연은 측정 도구를 만들어 숫자로 확인해요. 한국어·일본어 IME도 테스트 대상에 넣어요.

### 8. 오디오 (난이도 하~중)

- **문제**: CoreAudio 경로가 짧은 주기를 요청받으면 바쁘게 기다리면서 CPU를 써요. 마이크 문제도 있어요.
- **근거**: [Gcenx #157](https://github.com/Gcenx/macOS_Wine_builds/issues/157), [Highball #601](https://github.com/gauthierpiarrette/highball/issues/601)
- **miroe**: CoreAudio 저지연 경로를 측정해서 고쳐요. Highball 엔진의 오디오 보정 라이브러리(MIT)도 참고해요.

### 9. 동영상과 컷신 (난이도 중)

- **문제**: Windows 동영상 기능(Media Foundation)을 Wine은 GStreamer로 흉내 내요. 그래서 AAC 소리나 일부 형식에서 컷신이 깨져요. GStreamer를 따로 들고 다녀야 해서 크기도 커요.
- **근거**: Unity 게임 영상에서 AAC 오류 [#59414](https://bugs.winehq.org/show_bug.cgi?id=59414), MF 텍스처 플래그 [#59432](https://bugs.winehq.org/show_bug.cgi?id=59432), WMV2 영상 멈춤 [#60045](https://bugs.winehq.org/show_bug.cgi?id=60045)
- **miroe**: Mac에 이미 있는 하드웨어 디코더(VideoToolbox, AVFoundation)로 H.264·HEVC·AAC를 직접 풀어요. 더 빠르고 전력도 덜 쓰고, GStreamer가 필요 없는 형식이 늘어나요.

### 10. 글꼴과 한중일 문자 (난이도 하, Miro 사용자에게 중요)

- **문제**: macOS에서 GDI+가 한중일 문자를 네모(□)로 그려요. Windows 글꼴이 없으면 글자가 깨지거나 엉뚱한 글꼴로 나와요.
- **근거**: GDI+가 한중일 문자를 네모로 그림 [#60881](https://bugs.winehq.org/show_bug.cgi?id=60881), 벵골어 [#60181](https://bugs.winehq.org/show_bug.cgi?id=60181), 히브리어 [#44598](https://bugs.winehq.org/show_bug.cgi?id=44598)
- **miroe**: Windows 글꼴 이름(맑은 고딕, MS Gothic 등)을 macOS 시스템 글꼴로 자동 연결해요.
- **진행 (2026-11-27)**: `prefix/cjk-fonts.py`로 새 C: 드라이브의 실패가 152개 중 140개에서 8개(Segoe UI만)로 줄었어요. 다운로드는 없어요. 새로 찾은 문제: Wine의 GDI+가 Apple SD 산돌고딕 Neo, 히라기노 명조, Songti, Heiti를 찾지 못해요(GDI는 찾아요). 그래서 한국어는 지금 Arial Unicode MS에 연결해요. GDI+를 고치는 게 다음 일이에요.

### 11. 메모리 (난이도 중)

- **문제**: 애플 실리콘은 CPU와 GPU가 메모리를 같이 써요. 게임이 메모리 정보를 잘못 받으면 캐시를 너무 크게 잡아 스왑이 생기고 프레임이 떨어져요.
- **근거**: 메모리 사용량 보고가 macOS에서 틀림 [#60619](https://bugs.winehq.org/show_bug.cgi?id=60619) · [#60621](https://bugs.winehq.org/show_bug.cgi?id=60621), M4 Pro 24GB에서 RDR2가 메모리 증가와 스왑으로 느려짐 [Highball #398](https://github.com/gauthierpiarrette/highball/issues/398)
- **miroe**: 통합 메모리에 맞는 메모리·VRAM 값을 보고하고, 게임별 메모리 사용을 측정해요.

### 12. 네트워크 (난이도 하~중)

- **근거**: macOS 27.3에서 TCP 로컬 포트가 0으로 남음 [#60704](https://bugs.winehq.org/show_bug.cgi?id=60704), wineserver의 TCP 연결 나열 중 중단 [#60097](https://bugs.winehq.org/show_bug.cgi?id=60097), VPN 인터페이스가 있으면 런처가 멈춤 [#60432](https://bugs.winehq.org/show_bug.cgi?id=60432)
- **miroe**: 새 macOS 버전이 나오면 네트워크 테스트를 자동으로 돌려요.

### 13. 배포와 패키징 (난이도 하)

- **문제**: Homebrew의 Wine 패키지가 2026년 3분기부터 비활성화됐어요. Gcenx는 공식 WineHQ 패키지에 추가 패치를 넣지 말라는 요청을 받아서, 공식 빌드로는 DXMT 같은 기능을 쓸 수 없어요.
- **근거**: [#58946](https://bugs.winehq.org/show_bug.cgi?id=58946), [Gcenx #168](https://github.com/Gcenx/macOS_Wine_builds/issues/168), [DXMT #194의 Gcenx 답변](https://github.com/3Shain/dxmt/issues/194)
- **miroe**: 우리가 직접 빌드하고, 어떤 소스와 패치로 만들었는지 누구나 다시 빌드해서 확인할 수 있게 해요. 모든 부품은 SHA-256으로 고정해요(Miro가 이미 하는 방식이에요).

### 14. 처음 실행이 느림 (난이도 하)

- **문제**: Windows 환경(C: 드라이브)을 처음 만들 때 wineboot, Mono, Gecko 설치가 오래 걸려요.
- **miroe**: 미리 만들어 둔 환경 틀을 APFS 복제로 순식간에 펼쳐요. Miro의 복구 지점에서 쓰는 방식이에요.

### miroe도 못 푸는 것

- **커널 안티치트**(Valorant, Fortnite 등): Mac에서는 원리상 불가능해요. 우회하면 계정 정지 위험이 있어요. 실행 전에 알려 주기만 해요.
- **Windows 드라이버가 필요한 프로그램**, **16비트 프로그램**
- 다른 프로그램의 Intel 코드를 번역하지 않고 실행하는 것: 번역은 FEX나 Rosetta가 맡아요.

## miroe 설계 원칙

1. **애플 실리콘 전용**: ARM64 호스트 하나만 생각해요. Intel Mac, Linux, 32비트 호스트는 고려하지 않아요.
2. **Wine을 재료로, 약한 층은 Mac 고유 기술로 교체**: 위 목록에서 보듯 문제는 특정 층(동기화, 창, 입력, 동영상, 글꼴, 메모리)에 몰려 있어요. Windows API 전체를 새로 짜는 대신, 이 층들을 Metal, CoreAudio, GameController, VideoToolbox, Core Text 같은 Mac 기술로 바꿔요.
3. **공식 Wine을 따라가요**: 새 Wine 버전이 나오면 우리 패치를 다시 올리고, 화면 없는 테스트와 벤치마크로 확인해요. 공식 통로가 생기면 우리 우회(예: Miro Metal Bridge)는 은퇴시켜요.
4. **측정이 먼저**: 고치기 전에 재고, 고친 뒤에 다시 재요. 숫자로 나아지지 않으면 넣지 않아요.
5. **게임 없이 테스트**: 사용자 게임은 테스트에 쓰지 않아요. 직접 만든 중립 테스트 프로그램만 써요.

## 단계

1. **측정 도구**: 1프레임 시간이 Rosetta, Wine 경계, 그래픽 변환 중 어디서 쓰이는지 나눠 재요. 입력 지연, 메모리 측정도 만들어요.
2. **miroe 0.1**: 공식 Wine 소스로 애플 실리콘 전용 빌드를 자동화하고, Miro Metal Bridge와 DXMT를 넣어요. Miro의 실험 엔진으로 연결해요.
3. **빠른 성과**: 빠른 동기화(3번), 한중일 글꼴 연결(10번), 컨트롤러 지연(7번), 게임 모드(6번)
4. **ARM64 + FEX**: Rosetta 없이 실행(1·2번). macOS 28 전에 끝내야 해요.
5. **Mac 고유 층**: 동영상 하드웨어 디코딩(9번), 메모리 보고(11번), 전체 화면(6번)
