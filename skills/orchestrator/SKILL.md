---
name: o
description: VS 클론에서 둘 이상의 콘텐츠·시스템 영역을 함께 구현할 때 specialist 스킬 선택, TDD 순서, 통합 검증을 조율한다. 무기 하나, 적 하나, 패시브 하나처럼 단일 영역 변경에는 사용하지 말고 해당 godot-vs-* specialist를 직접 사용한다. 설계 토론, 단순 질문, 리뷰 전용 요청에도 사용하지 않는다.
---

# Orchestrator

복합 구현을 specialist 스킬과 공통 검증 계약으로 조율한다. Main의 직접 실행이 기본이다.

## 성공 조건

- 요청된 각 영역의 specialist 스킬을 정확히 선택한다.
- 영역별 RED → GREEN 순서를 보존한다.
- 공유 상태와 등록 지점을 통합 검증한다.
- 사용자 승인 없이 서브에이전트 모드로 전환하지 않는다.

## 라우팅

| 영역 | Specialist |
|---|---|
| 무기 | `godot-vs-weapon` |
| 적·보스 | `godot-vs-enemy` |
| 패시브 | `godot-vs-passive` |
| 픽업 | `godot-vs-pickup` |
| 보석 | `godot-vs-weapon-gem` |
| 진화·합성 | `godot-vs-evolution` |
| 캐릭터 | `godot-vs-character` |

단일 영역이면 이 스킬을 종료하고 해당 specialist만 사용한다.

## 직접 실행 워크플로우

1. 사용자에게 보이는 결과, 영역별 성공 조건, 통합 경계, 중단 조건을 정한다.
2. 각 specialist의 `SKILL.md`를 읽고 `AGENTS.md`의 TDD 절차를 따른다.
3. 공유 파일 충돌이 적은 순서로 한 영역씩 구현한다.
4. 각 영역에서 실패하는 focused test를 먼저 확인하고 최소 구현으로 통과시킨다.
5. 마지막 코드·테스트 수정 후 영향받는 focused/adjacent 검증을 실행한다.
6. 커밋 경계에서 `tools/run-gdunit.sh`로 전체 스위트를 한 번 실행한다.
7. 씬, 시그널, 리소스, UI, 물리, autoload가 바뀌면 전체 스위트 후 Godot MCP 런타임을 한 번 검증한다.
8. 검증이 통과하면 프로젝트 커밋 규칙에 따라 커밋하고 결과와 남은 우려를 보고한다.

직접 사용자 요청에서는 `.context/TASKS.md`의 다른 작업을 선택하지 않는다. 큐에서 선택한 작업만 `[~]`와 `[x]`로 갱신한다.

## 선택적 위임

사용자가 서브에이전트 또는 병렬 에이전트 작업을 명시적으로 요청한 경우에만 위임한다.

- 전체 트리에서 한 번에 한 직접 서브에이전트만 실행한다.
- 한 서브에이전트에 한 영역과 1–3개 production/test 파일 범위를 준다.
- 모든 할당에 다음 문장을 포함한다: `Do not spawn subagents. Use your own tools and return the result directly to Main.`
- 구현 에이전트가 terminal report를 반환하고 중지한 뒤 Main이 diff와 검증 근거를 검토한다.
- 독립 리뷰가 필요하고 위임 권한 범위에 포함될 때만 구현 에이전트 종료 후 reviewer를 시작한다.
- Main은 변경되지 않은 focused 결과를 재실행하지 않고, 최종 전체 스위트와 런타임 gate를 한 번 소유한다.

### Sol → Luna → Sol 순차 워크플로우

사용자가 이 명명된 흐름을 요청하거나 승인한 경우에만 사용한다. 역할 이름은 책임 계약이며, 해당 이름의 에이전트를 사용할 수 없으면 임의로 대체했다고 주장하지 말고 사용 가능한 에이전트와 역할을 명시한다.

Executor에는 `opencode-go`의 Luna를 우선 사용한다. 해당 Luna를 사용할 수 없을 때만 `openai-codex`의 Luna로 폴백하며, 폴백 사실과 이유를 Main에 명시한다. 두 Luna 모두 사용할 수 없으면 다른 에이전트를 Luna라고 부르지 않는다.

1. **Main — 계약 확정:** 사용자 요구를 해석하고 최상위 범위, 성공 조건, 변경 경계, 검증 명령, 커밋 경계를 확정한다. 최상위 계획을 Sol에 통째로 위임하지 않는다.
2. **Sol — Planner:** Main이 정한 계약 안에서 구현 순서, 파일 소유권, RED/GREEN 검증, 중단 조건을 구체화한다. 저장소를 수정하지 않고 계획 결과를 Main에 반환한 뒤 중지한다.
3. **Luna — Executor:** 확정된 범위만 TDD로 구현하고 focused 검증을 수행한다. 상태, 변경 파일, 테스트 명령·건수·종료 코드, 런타임 근거, 미해결 우려를 terminal report로 반환한 뒤 중지한다.
4. **Main — 중간 검토:** Luna의 diff와 검증 근거를 직접 확인한다. 계약 밖 변경이나 불충분한 근거가 있으면 리뷰 전에 범위를 바로잡는다.
5. **Sol — Reviewer:** Luna가 중지한 뒤 계획과 성공 조건 대비 누락, 회귀 위험, 테스트 적절성을 검토한다. 이 단계에서 직접 수정하지 않는다.
6. **Main — 종료:** 리뷰 지적을 직접 수정하거나 별도의 순차 수정 할당으로 처리하고, 필요한 전체 GdUnit4·Godot MCP gate와 커밋을 소유한다.

동일한 Sol의 Planner/Reviewer 재사용은 계획 일관성 리뷰이지 독립 리뷰가 아니다. 비단순·고위험 변경에서 독립성이 필요하면 Luna 종료 후 별도 reviewer를 사용한다. 모든 단계에서 직접 서브에이전트는 최대 한 명이며 이전 역할이 terminal result를 반환하고 중지하기 전에는 다음 역할을 시작하지 않는다.

## 실패 처리

- 실패가 구현에서 비롯되면 해당 영역의 최소 수정 후 영향받은 focused test부터 재실행한다.
- fixture나 transport만 실패하고 저장소 변경이 없으면 해당 gate만 한 번 재시도한다.
- 동일한 필수 전제가 계속 없거나 권한·제품 결정이 필요하면 범위를 넓히지 말고 blocker를 보고한다.
