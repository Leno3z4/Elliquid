export type StrategyAction = "DEPLOY" | "HOLD" | "REDUCE" | "EXIT";

export type StrategyPolicy = {
  targetInventoryBps: number;
  maxInventoryBps: number;
  maxDrawdownBps: number;
  minLiquidityCoverageBps: number;
};

export type StrategySnapshot = {
  inventoryBps: number;
  liquidityCoverageBps: number;
  drawdownBps: number;
  marketHealthy: boolean;
  executionFresh: boolean;
};

export type StrategyDecision = {
  action: StrategyAction;
  reason: string;
  urgency: "normal" | "high" | "critical";
};
