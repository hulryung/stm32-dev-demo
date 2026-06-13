# Soft NPU (FPGA) vs Hard NPU (MCU) — STM32N6 ↔ Zynq UltraScale+

같은 문제("카메라 영상에 신경망 추론을 돌린다")를 두 가지 방식으로 푼 것을 나란히 비교한다.

- **STM32N6570-DK** — 신경망 가속기(Neural-ART NPU)가 **실리콘에 고정**된 MCU. 이 저장소의 데모들.
- **MYIR MYD-CZU4EV (Zynq UltraScale+ XCZU4EV)** — FPGA 패브릭에 **직접 만든 soft NPU**
  (시스톨릭 어레이 + GEMM AXI 가속기 + 자체 컴파일러). `~/dev/fpga-test`.

> 한 줄 요약: **N6 = 빠르고 저전력이지만 고정된 하드웨어 / FPGA = 느리고 전력 더 먹지만 회로 자체를 바꿀 수 있다.**
> 칩 설계의 고전적 트레이드오프(ASIC형 vs 재구성형)를 실물 두 대로 보여주는 비교다.

---

## 1. 부품이 1:1로 대응한다

두 프로젝트는 사실상 같은 스택을 다른 층위에서 구현했다.

| 레이어 | Zyng FPGA (`fpga-test`) | STM32N6 (이 저장소) |
|---|---|---|
| 연산 엔진 | 직접 설계한 8×8 INT8 output-stationary **시스톨릭 어레이** (`examples/systolic`, 64 MAC) | **Neural-ART NPU** (하드와이어드) |
| 가속기 래핑 | `gemm_axi` — AXI4-Lite로 PS가 A·B 적재/start/C 읽기 | ST 드라이버 + `ll_aton` 런타임 |
| 모델 변환 툴 | `npu_compiler` — tflite→C 코드젠, 양자화 scale→requant (TVM BYOC식 PoC) | **ST Edge AI Core** — tflite/onnx→NPU C 코드 |
| 카메라 파이프라인 | `camera_npu` — V4L2 → GEMM NPU → 분류/모션 → TCP 스트림 | DCMIPP + ISP → NPU → LCD 오버레이 |
| 호스트 CPU | ARM Cortex-A53 ×4 @1.2GHz, PetaLinux | Cortex-M55 @800MHz (Helium), 베어메탈/FreeRTOS |
| 데이터 무브 | AXI **CDMA 버스트** (`examples/dma`, 799 MB/s 실측) | DCMIPP DMA, NPU 전용 메모리 경로 |
| 양자화 | INT8 / INT4 / packed PE | INT8 |

---

## 2. 하드웨어 스펙

| | Zynq XCZU4EV (soft NPU) | STM32N657 (Neural-ART) |
|---|---|---|
| 연산 자원 | FPGA ~192K 로직셀, DSP 슬라이스 | 고정 NPU 매크로 |
| NPU 클럭 | `pl_clk0` ~100 MHz (실측) | ~1 GHz NPU 클럭 |
| 피크 성능 | **~1 TOPS 이론치** (2000 MAC@250MHz, 미구현) / 실제 빌드는 64 MAC@100MHz | **~600 GOPS** (0.6 TOPS) INT8, ST 사양 |
| 호스트 | A53 ×4 + R5 ×2 + Mali-400 + **VCU 영상코덱** | Cortex-M55 단일 |
| 메모리 | 4GB DDR4 | 내부 SRAM + 외부 xSPI (내부 플래시 없음) |
| 전력 | PL+PS 합쳐 수 W 급 | 수십 mW ~ 1 W 급 |
| 재구성 | **비트스트림 교체로 회로 자체 변경** (~145ms 핫로드) | 불가 (모델만 교체) |

---

## 3. 성능 — 측정값 (정직하게 구분)

### FPGA 측 — `fpga-test` 실측 (보드 측정)
GEMM 1회(N=8 INT8) 적재 방식별 — `examples/dma/README.md`:

| 방식 | N=8 1회 | 비고 |
|---|---|---|
| mmio 비패킹 | 27 µs | 레지스터 단위 |
| wpack 패킹 | **7.3 µs** (3.72×) | 작은 NPU엔 최적 |
| CDMA 버스트 | 26.7 µs | N=8엔 setup 오버헤드 |

- 크로스오버: **작으면 mmio 패킹, N≈11부터 역전, N=24면 DMA가 5× 승**.
- CDMA 대역폭: **799 MB/s** DDR→DDR (256B~4MB 스윕 81→797 MB/s).
- `camera_npu` end-to-end: V4L2 + 8×8 GEMM NPU + 모션, **헤드리스 ~47 fps** (TCP 스트림).
- 비트스트림 핫로드 ~145 ms, `top.bit` 7.8 MB.

> 핵심: 이 soft NPU는 **8×8 타일(64 MAC)** 규모다. 작은 모델/연산엔 충분하고, 데이터무브
> 최적화(mmio packing ↔ CDMA)를 직접 실측해 정리한 게 강점. 절대 성능은 N6 NPU에 못 미친다.

### N6 측 — 사양 + 관측
- Neural-ART NPU INT8 ~600 GOPS (ST 사양).
- 이 저장소 데모들이 NPU에서 실시간 추론 → LCD 오버레이:
  - people-detection-tracking (YoloX)
  - multi-pose-estimation (YOLOv8-pose) — **fps는 LCD에 표시됨 (← 측정해 채울 칸)**
  - hand-landmarks
- 추론 fps/지연은 데모가 LCD에 직접 출력 (UART 미출력). 전력 실측은 ST의
  `x-cube-n6-ai-power-measurement` 데모로 가능.

| 지표 | Zynq soft NPU | N6 Neural-ART | 우세 |
|---|---|---|---|
| 절대 처리량(GOPS) | ~0.06 TOPS 실측 규모 | ~0.6 TOPS 사양 | **N6** (~10×) |
| 전력 효율(GOPS/W) | 낮음 (PL+PS 수 W) | 매우 높음 (<1 W) | **N6** |
| 커스텀 데이터플로우 | INT4·packed·임의 구조 | ST 지원 연산만 | **FPGA** |
| 개발 시간 | 길다 (RTL 설계·합성·타이밍) | 짧다 (모델만 컴파일) | **N6** |
| 학습/내부 가시성 | PE·버스·DMA까지 전부 | NPU는 블랙박스 | **FPGA** |

---

## 4. 언제 무엇을 쓰나
- **제품화/저전력 엣지 AI, 빠른 양산** → N6. 모델만 ST Edge AI Core로 컴파일하면 끝.
- **커스텀 연산/비표준 양자화(INT4 등)/HW 학습/가속기 자체 연구** → FPGA. 회로를 내가 정의.
- 둘 다 "카메라→NPU→결과" 동일 패턴이라, 같은 모델로 직접 비교가 가능하다(아래).

---

## 5. 머리맞대기(head-to-head) 재현 방법

같은 양자화 CNN 1개를 양쪽 NPU에 올려 fps/지연/전력을 잰다.

1. **공통 모델 선정** — `fpga-test/examples/camera_npu/gesture_model.h` 또는
   `npu_compiler/model_example.json` 수준의 작은 분류 CNN.
2. **FPGA 측** — `npu_compile.py`로 C 생성 → `camera_npu`로 fps/지연 측정 (`npu_bench`는
   같은 GEMM을 A53 SW vs NPU mmio로 비교).
3. **N6 측** — 같은 모델을 ST Edge AI Core로 변환(myST 로그인) → 보드에서 추론 시간 확인,
   전력은 `x-cube-n6-ai-power-measurement`.
4. **결과 정리** — 아래 표를 채운다.

| 모델 | 플랫폼 | ms/추론 | fps | 전력(mW) | GOPS/W |
|---|---|---|---|---|---|
| (공통 CNN) | Zynq soft NPU | | | | |
| (공통 CNN) | N6 Neural-ART | | | | |

---

## 6. "FPGA로도 이 스켈레톤(포즈)이 되나?"

**된다. 단, 세 가지 길이 있고 난이도·결과가 다르다.**

| 길 | 방법 | 실시간성 | 노력 | 성격 |
|---|---|---|---|---|
| **A. 지금의 8×8 soft NPU 그대로** | `npu_compiler`로 작은 포즈 모델(MoveNet-Lightning류) 타일링 추론 | 느림 (64 MAC@100MHz ≈ 6.4 GMAC/s → 수 fps, 무거운 최적화 필요) | 중 (SW 경로는 이미 있음) | 학습용. "내 NPU로 끝까지" |
| **B. 시스톨릭 어레이 확장** | DSP 슬라이스 활용해 16×16/32×16 INT8 어레이로 키움 (ZU4EV에 DSP ~728개, INT8 packing 시 DSP당 2 MAC) | 작은 모델 실시간 가능 (이미 적어둔 ~1 TOPS 이론치에 접근) | 큼 (RTL 재설계·타이밍 클로징) | 진짜 가속기 연구 |
| **C. AMD DPU + Vitis AI** | 미리 만들어진 CNN 가속 IP(DPU)를 PL에 올리고 Vitis AI로 모델 컴파일 | 실용적 실시간 (DPU B1152~B2304, 0.5~1+ TOPS) | 중 (PetaLinux + Vitis AI 런타임, **버전 호환 주의**) | 양산형. "FPGA로 실제 돌린다" |

- **스켈레톤 그리기 자체는 이미 해결돼 있다.** `camera_npu`가 카메라→NPU→**TCP 호스트 뷰어**
  파이프라인을 갖췄으니, 키포인트 좌표만 나오면 오버레이는 호스트(Mac viewer)나 HDMI/DP 출력으로
  그리면 된다. ST 데모가 LCD에 그리는 것과 같은 그림을 호스트에서 그리는 셈.
- **현실적 추천**: "FPGA에서 N6처럼 스켈레톤이 실시간으로 떴으면" 한다면 **길 C(DPU+Vitis AI)**가
  정답. 다만 DPU는 블랙박스 IP라 "내가 만든 NPU"의 색은 옅어진다. **교육·연구 목적이면 길 B**(어레이
  확장)가 당신 프로젝트의 서사("직접 만든 NPU로 포즈 추정")에 맞는다.
- **비교 관점의 결론**: N6는 포즈 모델이 **상자 밖에서(out-of-the-box)** 실시간으로 돈다. FPGA는
  같은 결과를 내려면 (B) 내 NPU를 키우거나 (C) DPU를 빌려야 한다 — 이 "직접 vs 기성"의 격차가 바로
  hard NPU와 soft NPU의 본질적 차이다.

> ⚠️ Vitis AI / DPU는 Vivado·PetaLinux 버전과 강하게 묶인다(이 보드 BSP는 2020.1 기준). DPU를 쓸
> 거면 Vitis AI 1.x(2020.1 계열) 호환 조합을 먼저 확인할 것.

---

## 참고
- FPGA 프로젝트: `~/dev/fpga-test` (worklog `docs/00-worklog.md`에 측정 근거)
- N6 빌드/플래시: 이 저장소 [README](../README.md), 빌드 [scripts/build.sh](../scripts/build.sh)
- ST 전력측정 데모: https://github.com/STMicroelectronics/x-cube-n6-ai-power-measurement
