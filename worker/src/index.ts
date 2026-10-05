import { Hono } from "hono";
import { cors } from "hono/cors";
import { drizzle } from "drizzle-orm/d1";
import { desc, eq } from "drizzle-orm";
import { liquidityRequests, projects, strategies, vaults } from "./db/schema";
import type { Env } from "./env";
import { evaluateStrategy } from "./strategy/engine";

const app = new Hono<{ Bindings: Env }>();

app.use("/api/*", async (c, next) => {
  const origins = c.env.API_ORIGIN ? c.env.API_ORIGIN.split(",").map((v) => v.trim()) : ["*"];
  return cors({
    origin: origins,
    allowHeaders: ["Content-Type", "Authorization"],
    allowMethods: ["GET", "POST", "OPTIONS"],
  })(c, next);
});

app.get("/", (c) =>
  c.json({
    service: "elliquid-api",
    environment: c.env.ENVIRONMENT ?? "development",
    ok: true,
  }),
);

app.get("/api/health", (c) => c.json({ ok: true, service: "elliquid-api", ts: Date.now() }));

app.get("/api/strategies", async (c) => {
  const db = drizzle(c.env.DB);
  const rows = await db.select().from(strategies).where(eq(strategies.active, true));
  return c.json({ data: rows });
});

app.get("/api/projects", async (c) => {
  const db = drizzle(c.env.DB);
  const rows = await db.select().from(projects).orderBy(desc(projects.createdAt));
  return c.json({ data: rows });
});

app.get("/api/liquidity-requests", async (c) => {
  const db = drizzle(c.env.DB);
  const status = c.req.query("status");
  const rows = status
    ? await db.select().from(liquidityRequests).where(eq(liquidityRequests.status, status as "open" | "filled" | "cancelled" | "expired")).orderBy(desc(liquidityRequests.createdAt))
    : await db.select().from(liquidityRequests).orderBy(desc(liquidityRequests.createdAt));

  return c.json({ data: rows });
});

app.get("/api/vaults", async (c) => {
  const db = drizzle(c.env.DB);
  const rows = await db.select().from(vaults).orderBy(desc(vaults.createdAt));
  return c.json({ data: rows });
});

app.post("/api/strategy/evaluate", async (c) => {
  const body = await c.req.json<{
    policy?: {
      targetInventoryBps: number;
      maxInventoryBps: number;
      maxDrawdownBps: number;
      minLiquidityCoverageBps: number;
    };
    snapshot?: {
      inventoryBps: number;
      liquidityCoverageBps: number;
      drawdownBps: number;
      marketHealthy: boolean;
      executionFresh: boolean;
    };
  }>();

  if (!body.policy || !body.snapshot) {
    return c.json({ error: "policy and snapshot are required" }, 400);
  }

  const decision = evaluateStrategy(body.policy, body.snapshot);
  return c.json({ data: decision });
});

app.post("/api/liquidity-requests", async (c) => {
  const body = await c.req.json<{
    projectId?: string;
    strategyId?: string;
    targetQuote?: string;
    durationSeconds?: number;
    maxInventoryBps?: number;
    liquidityFeeBps?: number;
  }>();

  if (!body.projectId || !body.strategyId || !body.targetQuote) {
    return c.json({ error: "projectId, strategyId and targetQuote are required" }, 400);
  }

  if ((body.durationSeconds ?? 0) < 3600) {
    return c.json({ error: "durationSeconds must be at least one hour" }, 400);
  }

  const db = drizzle(c.env.DB);
  const id = crypto.randomUUID();
  const createdAt = new Date();

  await db.insert(liquidityRequests).values({
    id,
    projectId: body.projectId,
    strategyId: body.strategyId,
    targetQuote: body.targetQuote,
    durationSeconds: body.durationSeconds ?? 86400,
    maxInventoryBps: body.maxInventoryBps ?? 1000,
    liquidityFeeBps: body.liquidityFeeBps ?? 300,
    status: "open",
    createdAt,
  });

  return c.json({ data: { id, status: "open" } }, 201);
});

export default app;
