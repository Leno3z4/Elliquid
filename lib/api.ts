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
