import type { Context } from "hono";
import { and, eq, lt } from "drizzle-orm";
import { verifyTypedData } from "viem";
import { drizzle } from "drizzle-orm/d1";
import { idempotencyKeys } from "../db/schema";
import type { Env } from "../env";
import {
  buildTypedAction,
  ELLIQUID_EIP712_DOMAIN,
  ELLIQUID_EIP712_TYPES,
  getRequestHash,
} from "@elliquid/shared/signing";

const AUTH_WINDOW_MS = 5 * 60 * 1000;
const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_BODY_BYTES = 16 * 1024;

export type SignedRequest = {
  wallet: `0x${string}`;
  idempotencyKey: string;
  requestHash: `0x${string}`;
  timestamp: number;
};

export async function authenticateSignedRequest(
  c: Context<{ Bindings: Env }>,
  action: string,
  body: unknown,
): Promise<SignedRequest | { error: Response }> {
  const contentLength = Number(c.req.header("Content-Length") ?? "0");
  if (contentLength > MAX_BODY_BYTES) {
    return { error: c.json({ error: "Request body too large" }, 413) };
  }

  const wallet = c.req.header("X-Elliquid-Address")?.trim().toLowerCase();
  const signature = c.req.header("X-Elliquid-Signature")?.trim() as `0x${string}` | undefined;
  const timestamp = Number(c.req.header("X-Elliquid-Timestamp")?.trim());
  const idempotencyKey = c.req.header("Idempotency-Key")?.trim();

  if (!wallet || !signature || !Number.isSafeInteger(timestamp) || !idempotencyKey) {
    return { error: c.json({ error: "Signed request headers are required" }, 401) };
  }
  if (!/^0x[0-9a-f]{40}$/.test(wallet) || !/^0x[0-9a-fA-F]{130}$/.test(signature)) {
    return { error: c.json({ error: "Invalid wallet or signature format" }, 400) };
  }
  if (idempotencyKey.length < 16 || idempotencyKey.length > 128 || !/^[A-Za-z0-9._:-]+$/.test(idempotencyKey)) {
    return { error: c.json({ error: "Invalid Idempotency-Key" }, 400) };
  }
  if (Math.abs(Date.now() - timestamp) > AUTH_WINDOW_MS) {
    return { error: c.json({ error: "Signed request is outside the replay window" }, 401) };
  }

  const endpoint = new URL(c.req.url).pathname;
  const requestHash = getRequestHash(endpoint, action, body);
  const message = buildTypedAction({
    action,
    endpoint,
    idempotencyKey,
    requestHash,
    timestamp,
  });

  let valid = false;
  try {
    valid = await verifyTypedData({
      address: wallet as `0x${string}`,
      domain: ELLIQUID_EIP712_DOMAIN,
      types: ELLIQUID_EIP712_TYPES,
      primaryType: "ElliquidAction",
      message,
      signature,
    });
  } catch {
    valid = false;
  }

  if (!valid) return { error: c.json({ error: "Invalid EIP-712 signature" }, 401) };

  return {
    wallet: wallet as `0x${string}`,
    idempotencyKey,
    requestHash,
    timestamp,
  };
}

export async function reserveIdempotency(
  c: Context<{ Bindings: Env }>,
  request: SignedRequest,
) {
  const db = drizzle(c.env.DB);
  const now = new Date();
  const expiresAt = new Date(now.getTime() + IDEMPOTENCY_TTL_MS);

  await db.delete(idempotencyKeys).where(and(
    eq(idempotencyKeys.wallet, request.wallet),
    eq(idempotencyKeys.key, request.idempotencyKey),
    lt(idempotencyKeys.expiresAt, now),
  ));

  const inserted = await db.insert(idempotencyKeys).values({
    wallet: request.wallet,
    key: request.idempotencyKey,
    endpoint: new URL(c.req.url).pathname,
    requestHash: request.requestHash,
    status: "processing",
    createdAt: now,
    expiresAt,
  }).onConflictDoNothing();

  if (inserted.rowsAffected === 1) return { state: "new" as const };

  const rows = await db.select().from(idempotencyKeys).where(and(
    eq(idempotencyKeys.wallet, request.wallet),
    eq(idempotencyKeys.key, request.idempotencyKey),
  )).limit(1);

  const row = rows[0];
  if (!row || row.requestHash !== request.requestHash || row.endpoint !== new URL(c.req.url).pathname) {
    return { state: "conflict" as const };
  }
  if (row.status === "completed" && row.responseStatus !== null && row.responseBody !== null) {
    return { state: "completed" as const, status: row.responseStatus, body: row.responseBody };
  }
  return { state: "processing" as const };
}

export async function completeIdempotency(
  c: Context<{ Bindings: Env }>,
  request: SignedRequest,
  status: number,
  body: unknown,
) {
  const db = drizzle(c.env.DB);
  await db.update(idempotencyKeys).set({
    status: "completed",
    responseStatus: status,
    responseBody: JSON.stringify(body),
  }).where(and(
    eq(idempotencyKeys.wallet, request.wallet),
    eq(idempotencyKeys.key, request.idempotencyKey),
  ));
}

export async function releaseIdempotency(c: Context<{ Bindings: Env }>, request: SignedRequest) {
  const db = drizzle(c.env.DB);
  await db.delete(idempotencyKeys).where(and(
    eq(idempotencyKeys.wallet, request.wallet),
    eq(idempotencyKeys.key, request.idempotencyKey),
  ));
}
