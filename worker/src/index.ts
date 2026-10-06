import { Hono } from "hono";
import { cors } from "hono/cors";
import { drizzle } from "drizzle-orm/d1";
import { and, desc, eq } from "drizzle-orm";
import { liquidityRequests, projects, strategies, vaults } from "./db/schema";
import type { Env } from "./env";
import { evaluateStrategy } from "./strategy/engine";
import { authenticateSignedRequest, completeIdempotency, releaseIdempotency, reserveIdempotency } from "./security/auth";
import { getElysiumClient } from "./chain/elysium";
import { createOnchainRequest, executeVaultAdapter, fillOnchainRequest, reconcileExecution, reconcilePendingExecutions } from "./execution/service";
import type { Hex } from "viem";

const app = new Hono<{ Bindings: Env }>();

async function reserveWriteOrReplay(
  c: Parameters<typeof reserveIdempotency>[0],
  auth: Parameters<typeof reserveIdempotency>[1],
) {
  const reservation = await reserveIdempotency(c, auth);
  if (reservation.state === "completed") {
    return new Response(reservation.body, {
      status: reservation.status,
      headers: {
        "Content-Type": "application/json",
        "X-Idempotent-Replay": "true",
      },
    });
  }
  if (reservation.state === "processing") {
    return c.json({
      error: "Request with this Idempotency-Key is already processing",
    }, 409);
  }
  if (reservation.state === "conflict") {
    return c.json({
      error: "Idempotency-Key was already used for a different request",
    }, 409);
  }
  return null;
}

app.use("/api/*", async (c, next) => {
  if (c.req.method !== "OPTIONS") {
    const { success } = await c.env.PUBLIC_RATE_LIMITER.limit({ key: `${c.req.header('CF-Connecting-IP') ?? 'unknown'}:${new URL(c.req.url).pathname}` });
    if (!success) return c.json({ error: "Rate limit exceeded" }, 429);
  }

  const origins = c.env.API_ORIGIN ? c.env.API_ORIGIN.split(",").map((v) => v.trim()) : ["*"];
  return cors({
    origin: origins,
    allowHeaders: ["Content-Type", "Authorization", "X-Elliquid-Address", "X-Elliquid-Signature", "X-Elliquid-Timestamp", "Idempotency-Key"],
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

app.get("/api/chain/status", async (c) => {
  const client = getElysiumClient(c.env);
  const [chainId, blockNumber] = await Promise.all([
    client.getChainId(),
    client.getBlockNumber(),
  ]);

  return c.json({
    data: {
      network: "Elysium Testnet",
      expectedChainId: 99801,
      chainId,
      blockNumber: blockNumber.toString(),
      rpcConfigured: Boolean(c.env.ELYSIUM_RPC_URL),
    },
  });
});

app.get("/api/strategies", async (c) => {
  const db = drizzle(c.env.DB);
  const rows = await db.select().from(strategies).where(eq(strategies.active, true)).limit(100);
  return c.json({ data: rows });
});

app.get("/api/projects", async (c) => {
  const db = drizzle(c.env.DB);
  const rows = await db.select().from(projects).orderBy(desc(projects.createdAt)).limit(100);
  return c.json({ data: rows });
});

app.get("/api/liquidity-requests", async (c) => {
  const db = drizzle(c.env.DB);
  const status = c.req.query("status");
  const rows = status
    ? await db.select().from(liquidityRequests).where(eq(liquidityRequests.status, status as "open" | "filled" | "cancelled" | "expired")).orderBy(desc(liquidityRequests.createdAt))
    : await db.select().from(liquidityRequests).orderBy(desc(liquidityRequests.createdAt)).limit(100);

  return c.json({ data: rows });
});

app.get("/api/vaults", async (c) => {
  const db = drizzle(c.env.DB);
  const rows = await db.select().from(vaults).orderBy(desc(vaults.createdAt)).limit(100);
  return c.json({ data: rows });
});

app.post("/api/execution/:actionKey/reconcile", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => ({}));
  const auth = await authenticateSignedRequest(
    c,
    "reconcile-execution",
    body,
  );
  if ("error" in auth) return auth.error;

  const replay = await reserveWriteOrReplay(c, auth);
  if (replay) return replay;

  try {
    const result = await reconcileExecution(
      c.env,
      c.req.param("actionKey"),
    );
    const response = { data: result };
    await completeIdempotency(c, auth, result.state === "pending" ? 202 : 200, response);
    return c.json(response, result.state === "pending" ? 202 : 200);
  } catch (error) {
    await releaseIdempotency(c, auth);
    throw error;
  }
});

app.post("/api/liquidity-requests/:id/onchain", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => ({}));
  const auth = await authenticateSignedRequest(c, "create-onchain-liquidity-request", body);
  if ("error" in auth) return auth.error;

  const allowed = await c.env.WRITE_RATE_LIMITER.limit({
    key: "wallet:" + auth.wallet,
  });
  if (!allowed.success) return c.json({ error: "Write rate limit exceeded" }, 429);

  const replay = await reserveWriteOrReplay(c, auth);
  if (replay) return replay;

  const id = c.req.param("id");
  const db = drizzle(c.env.DB);
  const rows = await db.select().from(liquidityRequests)
    .where(eq(liquidityRequests.id, id))
    .limit(1);
  const request = rows[0];
  if (!request) return c.json({ error: "Liquidity request not found" }, 404);

  const projectRows = await db.select().from(projects)
    .where(eq(projects.id, request.projectId))
    .limit(1);
  const project = projectRows[0];
  if (!project || project.wallet.toLowerCase() !== auth.wallet.toLowerCase()) {
    return c.json({ error: "Signed wallet does not own this request" }, 403);
  }

  try {
    const result = await createOnchainRequest(c.env, id);
    const response = { data: result };
    await completeIdempotency(c, auth, result.state === "confirmed" ? 200 : 202, response);
    return c.json(response, result.state === "confirmed" ? 200 : 202);
  } catch (error) {
    await releaseIdempotency(c, auth);
    throw error;
  }
});

app.post("/api/liquidity-requests/:id/fill", async (c) => {
  const body = await c.req.json<Record<string, unknown>>().catch(() => ({}));
  const auth = await authenticateSignedRequest(c, "fill-liquidity-request", body);
  if ("error" in auth) return auth.error;

  const replay = await reserveWriteOrReplay(c, auth);
  if (replay) return replay;

  try {
    const result = await fillOnchainRequest(
      c.env,
      c.req.param("id"),
      auth.wallet,
    );
    const response = { data: result };
    await completeIdempotency(c, auth, result.state === "confirmed" ? 200 : 202, response);
    return c.json(response, result.state === "confirmed" ? 200 : 202);
  } catch (error) {
    await releaseIdempotency(c, auth);
    throw error;
  }
});

app.post("/api/liquidity-requests/:id/execute", async (c) => {
  const body = await c.req.json<{
    vaultId?: string;
    assetsToFund?: string;
    adapterData?: string;
  }>().catch(() => ({} as {
    vaultId?: string;
    assetsToFund?: string;
    adapterData?: string;
  }));

  const auth = await authenticateSignedRequest(
    c,
    "execute-liquidity-request",
    body,
  );
  if ("error" in auth) return auth.error;

  if (!body.vaultId || !body.assetsToFund || !body.adapterData) {
    return c.json({
      error: "vaultId, assetsToFund and adapterData are required",
    }, 400);
  }

  const replay = await reserveWriteOrReplay(c, auth);
  if (replay) return replay;

  try {
    const result = await executeVaultAdapter(c.env, {
      requestId: c.req.param("id"),
      vaultId: body.vaultId,
      assetsToFund: body.assetsToFund,
      adapterData: body.adapterData as Hex,
      signedWallet: auth.wallet,
    });
    const response = { data: result };
    await completeIdempotency(c, auth, result.state === "confirmed" ? 200 : 202, response);
    return c.json(response, result.state === "confirmed" ? 200 : 202);
  } catch (error) {
    await releaseIdempotency(c, auth);
    throw error;
  }
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

  const policyValues = [
    body.policy.targetInventoryBps,
    body.policy.maxInventoryBps,
    body.policy.maxDrawdownBps,
    body.policy.minLiquidityCoverageBps,
  ];
  const snapshotValues = [
    body.snapshot.inventoryBps,
    body.snapshot.liquidityCoverageBps,
    body.snapshot.drawdownBps,
  ];
  if (
    [...policyValues, ...snapshotValues].some((value) => !Number.isFinite(value) || value < 0 || value > 10000) ||
    typeof body.snapshot.marketHealthy !== "boolean" ||
    typeof body.snapshot.executionFresh !== "boolean"
  ) {
    return c.json({ error: "Invalid strategy policy or snapshot bounds" }, 400);
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

  const auth = await authenticateSignedRequest(c, "create-liquidity-request", body);
  if ("error" in auth) return auth.error;

  const { success: writeAllowed } = await c.env.WRITE_RATE_LIMITER.limit({ key: `wallet:${auth.wallet}` });
  if (!writeAllowed) return c.json({ error: "Write rate limit exceeded" }, 429);

  if (!body.projectId || !body.strategyId || !body.targetQuote) {
    return c.json({ error: "projectId, strategyId and targetQuote are required" }, 400);
  }

  if (!/^\d+$/.test(body.targetQuote) || body.targetQuote.length > 78 || /^0+$/.test(body.targetQuote)) {
    return c.json({ error: "targetQuote must be a positive integer amount in base units" }, 400);
  }

  const minDurationSeconds = Number(c.env.MIN_REQUEST_DURATION_SECONDS ?? 3600);
  const maxDurationSeconds = Number(c.env.MAX_REQUEST_DURATION_SECONDS ?? 30 * 24 * 3600);
  const maxInventoryBps = Number(c.env.MAX_INVENTORY_BPS ?? 10000);
  const maxLiquidityFeeBps = Number(c.env.MAX_LIQUIDITY_FEE_BPS ?? 1000);
  if (!Number.isInteger(minDurationSeconds) || minDurationSeconds < 60 ||
      !Number.isInteger(maxDurationSeconds) || maxDurationSeconds < minDurationSeconds || maxDurationSeconds > 90 * 24 * 3600 ||
      !Number.isInteger(maxInventoryBps) || maxInventoryBps < 0 || maxInventoryBps > 10000 ||
      !Number.isInteger(maxLiquidityFeeBps) || maxLiquidityFeeBps < 0 || maxLiquidityFeeBps > 1000) {
    return c.json({ error: "Invalid request limit configuration" }, 500);
  }
  if ((body.durationSeconds ?? 0) < minDurationSeconds || (body.durationSeconds ?? 0) > maxDurationSeconds) {
    return c.json({ error: "durationSeconds is outside the configured request limits" }, 400);
  }
  if ((body.maxInventoryBps ?? 1000) < 0 || (body.maxInventoryBps ?? 1000) > maxInventoryBps) {
    return c.json({ error: "maxInventoryBps is outside the configured request limit" }, 400);
  }
  if ((body.liquidityFeeBps ?? 300) < 0 || (body.liquidityFeeBps ?? 300) > maxLiquidityFeeBps) {
    return c.json({ error: "liquidityFeeBps is outside the configured request limit" }, 400);
  }

  const db = drizzle(c.env.DB);
  const projectRows = await db.select().from(projects).where(eq(projects.id, body.projectId)).limit(1);
  const project = projectRows[0];
  if (!project) return c.json({ error: "Project not found" }, 404);
  if (project.wallet.toLowerCase() !== auth.wallet.toLowerCase()) {
    return c.json({ error: "Signed wallet does not own this project" }, 403);
  }

  const strategyRows = await db.select().from(strategies).where(and(
    eq(strategies.id, body.strategyId),
    eq(strategies.active, true),
  )).limit(1);
  if (!strategyRows[0]) return c.json({ error: "Active strategy not found" }, 404);

  const reservation = await reserveIdempotency(c, auth);
  if (reservation.state === "completed") {
    return new Response(reservation.body, {
      status: reservation.status,
      headers: { "Content-Type": "application/json", "X-Idempotent-Replay": "true" },
    });
  }
  if (reservation.state === "processing") {
    return c.json({ error: "Request with this Idempotency-Key is already processing" }, 409);
  }
  if (reservation.state === "conflict") {
    return c.json({ error: "Idempotency-Key was already used for a different request" }, 409);
  }

  try {
    const id = crypto.randomUUID();
    const createdAt = new Date();

    await db.insert(liquidityRequests).values({
      id,
      projectId: body.projectId,
      strategyId: body.strategyId,
      targetQuote: body.targetQuote,
      requestKey: `${auth.wallet}:${auth.idempotencyKey}`,
      durationSeconds: body.durationSeconds ?? 86400,
      maxInventoryBps: body.maxInventoryBps ?? 1000,
      liquidityFeeBps: body.liquidityFeeBps ?? 300,
      status: "open",
      createdAt,
    });

    const response = { data: { id, status: "open" } };
    await completeIdempotency(c, auth, 201, response);
    return c.json(response, 201);
  } catch (error) {
    await releaseIdempotency(c, auth);
    throw error;
  }
});

const handler = {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext) {
    await reconcilePendingExecutions(env);
  },
};

export default handler;


app.onError((error, c) => {
  console.error("Unhandled API error", error);
  return c.json({ error: "Internal server error" }, 500);
});
