import type { Context } from "hono";
import { and, eq, lt } from "drizzle-orm";
import { verifyMessage, keccak256, stringToHex } from "viem";
import { drizzle } from "drizzle-orm/d1";
import { idempotencyKeys } from "../db/schema";
import type { Env } from "../env";

const AUTH_WINDOW_MS = 5 * 60 * 1000;
const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000;

export type SignedRequest = {
  wallet: `0x${string}`;
  idempotencyKey: string;
  requestHash: `0x${string}`;
  timestamp: number;
};

function canonicalize(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonicalize).join(",") + "]";
  const record = value as Record<string, unknown>;
  return "{" + Object.keys(record).sort().map((key) => JSON.stringify(key) + ":" + canonicalize(record[key])).join(",") + "}";
}

export function signedPayloadHash(endpoint: string, action: string, body: unknown) {
  return keccak256(stringToHex(endpoint + "|" + action + "|" + canonicalize(body)));
}

function buildMessage(args: {
  address: string;
  action: string;
  endpoint: string;
  idempotencyKey: string;
  timestamp: number;
  requestHash: string;
}) {
  return [
    "Elliquid signed action",
    "version: 1",
    `action: ${args.action}`,
    `endpoint: ${args.endpoint}`,
    `address: ${args.address}`,
    `timestamp: ${args.timestamp}`,
    `idempotency-key: ${args.idempotencyKey}`,
    `request-hash: ${args.requestHash}`,
  ].join("\n");
}

export async function authenticateSignedRequest(
  c: Context<{ Bindings: Env }>,
  action: string,
  body: unknown,
): Promise<SignedRequest | { error: Response }> {
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
  if (idempotencyKey.length < 16 || idempotencyKey.length > 128) {
    return { error: c.json({ error: "Invalid Idempotency-Key" }, 400) };
  }
  if (Math.abs(Date.now() - timestamp) > AUTH_WINDOW_MS) {
    return { error: c.json({ error: "Signed request is outside the replay window" }, 401) };
  }

  const endpoint = new URL(c.req.url).pathname;
  const requestHash = signedPayloadHash(endpoint, action, body);
  const message = buildMessage({
    address: wallet,
    action,
    endpoint,
    idempotencyKey,
    timestamp,
    requestHash,
  });

  let valid = false;
  try {
    valid = await verifyMessage({
      address: wallet as `0x${string}`,
      message,
      signature,
    });
  } catch {
    valid = false;
  }

  if (!valid) return { error: c.json({ error: "Invalid signed request" }, 401) };

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
