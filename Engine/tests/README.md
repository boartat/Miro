# 화면 없는 엔진 테스트

게임도 화면도 쓰지 않고 엔진과 그래픽 방식을 확인하는 작은 Windows 프로그램들이에요. 창을 만들 때는 화면 밖(-20000, -20000)에 만들고, 실제로 화면 밖에 있는지 확인한 뒤에만 보여요.

| 파일 | 확인하는 것 | 결과 |
| --- | --- | --- |
| `d3d11-smoke-test.cs` | D3D11 장치·스왑체인, 셰이더로 그리기, 픽셀 읽기, 창 크기 변경 후 다시 확인 | `PASS` / `FAIL …` |
| `d3d12-compute-test.cs` | D3D12 장치, 루트 시그니처, 컴퓨트 PSO, 결과 버퍼 읽기 | `PASS` / `FAIL …` |
| `pointer-api-test.cs` | Unity 6.3이 시작할 때 부르는 `IsMouseInPointerEnabled` / `EnableMouseInPointer` | `PASS` / `FAIL …` |
| `d3d11-bench.cs` | 무거운 셰이더와 그리기 명령 처리 속도, `soak <초>`로 연속 실행 | 1프레임당 ms |
| `cjk-text-test.cs` | 한국어·일본어·중국어가 GDI+와 GDI에서 실제 글자로 그려지는지(네모 □가 아닌지), 글꼴 19개 | `PASS` / `FAIL n cases` |

## 빌드

.NET Framework 4.8이 설치된 C: 드라이브에서, Wine 안의 `csc.exe`로 컴파일해요. Wine Mono에 든 컴파일러는 동작하지 않아요.

```bash
WINEPREFIX=<C: 드라이브> WINEDLLOVERRIDES="winedbg.exe=d" wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /platform:x64 /optimize /out:dxtest.exe d3d11-smoke-test.cs
```

32비트로 시험하려면 `/platform:x86`으로 빌드해요. `d3d11-bench.cs`와 `d3d12-compute-test.cs`는 먼저 `compile <폴더>`로 셰이더 바이트코드를 만들어 두고, 그다음 `run <폴더>` / `<폴더>`로 실행해요.

## 실행

`WINEDLLOVERRIDES`로 그래픽 방식을 골라요.

- **DXMT**: `d3d11,dxgi,d3d10core,winemetal=b`
- **DXVK**: `d3d11,dxgi,d3d10core=n,b`
- **D3DMetal**: 클래식 엔진 기본값이에요.

항상 `winedbg.exe=d`를 같이 넣어 두세요. 오류가 나도 디버거 창이 뜨지 않아요.
