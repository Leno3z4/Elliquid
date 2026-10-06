export type ApiStrategy = {
  id: string;
  name: string;
  slug: string;
  description: string;
  risk: "low" | "medium" | "high";
  targetApy: number | null;
  managementFeeBps: number;
  performanceFeeBps: number;
  active: boolean;
};

function apiBaseUrl() {
  const value = process.env.NEXT_PUBLIC_ELLIQUID_API_URL?.trim();
  return value ? value.replace(/\/$/, "") : null;
}

export async function fetchStrategies(): Promise<ApiStrategy[] | null> {
  const base = apiBaseUrl();
  if (!base) return null;

  const res = await fetch(base + "/api/strategies", {
    headers: { Accept: "application/json" },
    cache: "no-store",
  });

  if (!res.ok) throw new Error("Strategy API returned " + res.status);
  const json = (await res.json()) as { data?: ApiStrategy[] };
  return json.data ?? [];
}

export function isApiConfigured() {
  return apiBaseUrl() !== null;
}


export type ApiProject = {
  id: string;
  name: string;
  slug: string;
  wallet: string;
  baseToken: string;
  quoteToken: string;
  verified: boolean;
  createdAt: string;
};

export type ApiLiquidityRequest = {
  id: string;
  projectId: string;
  strategyId: string;
  targetQuote: string;
  durationSeconds: number;
  maxInventoryBps: number;
  liquidityFeeBps: number;
  status: "open" | "filled" | "cancelled" | "expired";
  createdAt: string;
  onchainRequestId: number | null;
  lastTxHash: string | null;
};

export async function fetchProjects(): Promise<ApiProject[] | null> {
  const base = apiBaseUrl();
  if (!base) return null;
  const res = await fetch(base + "/api/projects", {
    headers: { Accept: "application/json" },
    cache: "no-store",
  });
  if (!res.ok) throw new Error("Projects API returned " + res.status);
  const json = (await res.json()) as { data?: ApiProject[] };
  return json.data ?? [];
}

export async function fetchLiquidityRequests(): Promise<ApiLiquidityRequest[] | null> {
  const base = apiBaseUrl();
  if (!base) return null;
  const res = await fetch(base + "/api/liquidity-requests", {
    headers: { Accept: "application/json" },
    cache: "no-store",
  });
  if (!res.ok) throw new Error("Liquidity request API returned " + res.status);
  const json = (await res.json()) as { data?: ApiLiquidityRequest[] };
  return json.data ?? [];
}
