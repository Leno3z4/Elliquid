export type RiskLevel = "low" | "medium" | "high";

export type Strategy = {
  id: string;
  name: string;
  slug: string;
  description: string;
  risk: RiskLevel;
  targetApy: number | null;
  managementFeeBps: number;
  performanceFeeBps: number;
  active: boolean;
};

export type Project = {
  id: string;
  name: string;
  slug: string;
  wallet: string;
  baseToken: string;
  quoteToken: string;
  verified: boolean;
};

export type LiquidityRequestStatus = "open" | "filled" | "cancelled" | "expired";

export type LiquidityRequest = {
  id: string;
  projectId: string;
  strategyId: string;
  targetQuote: string;
  durationSeconds: number;
  maxInventoryBps: number;
  liquidityFeeBps: number;
  status: LiquidityRequestStatus;
};

export type Vault = {
  id: string;
  name: string;
  strategyId: string;
  assetSymbol: string;
  chainId: number;
  contractAddress: string | null;
  tvl: string;
  active: boolean;
};
