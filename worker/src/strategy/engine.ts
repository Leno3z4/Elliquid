import type { StrategyDecision, StrategyPolicy, StrategySnapshot } from "./types";

export function evaluateStrategy(
  policy: StrategyPolicy,
  snapshot: StrategySnapshot,
): StrategyDecision {
  if (!snapshot.executionFresh) {
    return {
      action: "HOLD",
      reason: "Execution data is stale; do not change capital allocation.",
      urgency: "high",
    };
  }

  if (!snapshot.marketHealthy) {
    return {
      action: "REDUCE",
      reason: "Market health is outside the strategy's safe operating regime.",
      urgency: "high",
    };
  }

  if (snapshot.drawdownBps >= policy.maxDrawdownBps) {
    return {
      action: "EXIT",
      reason: "Configured drawdown circuit breaker has been reached.",
      urgency: "critical",
    };
  }

  if (snapshot.inventoryBps > policy.maxInventoryBps) {
    return {
      action: "REDUCE",
      reason: "Inventory is above the strategy maximum.",
      urgency: "high",
    };
  }

  if (snapshot.liquidityCoverageBps < policy.minLiquidityCoverageBps) {
    return {
      action: "DEPLOY",
      reason: "Liquidity coverage is below the strategy minimum.",
      urgency: "normal",
    };
  }

  if (snapshot.inventoryBps < policy.targetInventoryBps) {
    return {
      action: "DEPLOY",
      reason: "Inventory is below the strategy target while market conditions are healthy.",
      urgency: "normal",
    };
  }

  return {
    action: "HOLD",
    reason: "Portfolio is inside the strategy's operating envelope.",
    urgency: "normal",
  };
}
