# STM32N6 AI Demo Workspace

STM32N6570-DK (STM32N657, Cortex-M55 + Neural-ART NPU) 보드에서 엣지 AI 데모를 실행하기 위한 작업 공간.

## 하드웨어

- 보드: [STM32N6570-DK](https://www.st.com/en/evaluation-tools/stm32n6570-dk.html) — LCD 터치스크린 + IMX335 카메라 모듈
- 연결: USB-C to USB-C 케이블로 Mac에 **직결** (허브/모니터 경유 시 플래싱 실패)
- 시리얼 콘솔: `/dev/cu.usbmodem102`, 115200 8N1

## 필요 도구

| 도구 | 버전 | 설치 |
|---|---|---|
| STM32CubeProgrammer | 2.22.0 | st.com 다운로드 (myST 로그인) |
| Arm GNU Toolchain | 15.2 | `brew install --cask gcc-arm-embedded` |
| probe-rs (선택) | 0.31 | `brew install probe-rs-tools` |
| ST Edge AI Core (커스텀 모델용) | 3.x | st.com 다운로드 (myST 로그인) |

`STM32_Programmer_CLI` 경로:

```
/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/Resources/bin
```

## 부트 모드 (보드 뒷면 DIP 스위치)

STM32N6는 내장 플래시가 없어 외부 플래시(MX66UW1G45G)에 펌웨어를 굽는다.

| 모드 | BOOT0 (SW2) | BOOT1 (SW1) | 용도 |
|---|---|---|---|
| 개발 모드 | L | **H (오른쪽)** | 플래시 프로그래밍 |
| 플래시 부팅 | L | **L (왼쪽)** | 데모 실행 |

모드 변경 후 반드시 전원 리셋(USB 재연결).

## 플래싱

```bash
BIN="/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/Resources/bin"
DKEL="$BIN/ExternalLoader/MX66UW1G45G_STM32N6570-DK.stldr"

"$BIN/STM32_Programmer_CLI" -c port=SWD freq=1000 mode=HOTPLUG -el "$DKEL" -hardRst \
  -w x-cube-n6-ai-people-detection-tracking/Binary/STM32N6570-DK/x-cube-n6-ai-people-detection-tracking-dk.hex
```

> **주의:** macOS에서 기본 SWD 속도(8MHz)로는 대용량 쓰기 중 `libusb: pipe is stalled` 에러로 실패한다.
> 반드시 `freq=1000`을 사용할 것. 실패 후 `DEV_USB_COMM_ERR`가 나오면 USB 케이블을 재연결해야 한다.

절차: 개발 모드로 전환 → 플래싱 → 플래시 부팅 모드로 복귀 → 전원 리셋.

## 데모

- `x-cube-n6-ai-people-detection-tracking/` (서브모듈) — YoloX 사람 감지 + 추적, NPU 가속.
  프리빌트 hex 포함, 소스 빌드는 `make -j8` 후 `STM32_SigningTool_CLI` 서명 필요 (README 참고).
- 그 외 ST 공개 데모: [multi-pose-estimation](https://github.com/STMicroelectronics/x-cube-n6-ai-multi-pose-estimation),
  [face-landmarks](https://github.com/STMicroelectronics/x-cube-n6-ai-face-landmarks),
  [hand-landmarks](https://github.com/STMicroelectronics/x-cube-n6-ai-hand-landmarks),
  [h264-usb-uvc](https://github.com/STMicroelectronics/x-cube-n6-ai-h264-usb-uvc)
