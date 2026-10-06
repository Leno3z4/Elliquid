import { and, eq } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { executionIntents } from "../db/schema";
import type { Env } from "../env";

export type ExecutionStatus =
  | "prepared"
  | "broadcast"
  | "confirmed"
  | "failed_before_broadcast"
  | "failed_after_broadcast";

export async function claimExecution(
  env: Env,
  args: { actionKey: string; vaultId?: string; action: string; referenceId?: string },
) {
  const db = drizzle(env.DB);
  const now = new Date();

  const inserted = await db.insert(executionIntents).values({
    actionKey: args.actionKey,
    vaultId: args.vaultId,
    action: args.action,
    referenceId: args.referenceId,
    status: "prepared",
    createdAt: now,
    updatedAt: now,
  }).onConflictDoNothing();

  if (inserted.meta.changes === 1) {
    return { state: "claimed" as const };
  }

  const rows = await db.select().from(executionIntents)
    .where(eq(executionIntents.actionKey, args.actionKey))
    .limit(1);

  const row = rows[0];
  if (!row) return { state: "missing" as const };
  if (row.action !== args.action || row.vaultId !== (args.vaultId ?? null)) {
    return { state: "conflict" as const };
  }

  return { state: "existing" as const, row };
}

export async function prepareExecution(
  env: Env,
  actionKey: string,
  args: { fromAddress: string; nonce: number; txHash: string },
) {
  const db = drizzle(env.DB);
  if (!/^0x[0-9a-fA-F]{40}$/.test(args.fromAddress)) throw new Error("INVALID_FROM_ADDRESS");
  if (!Number.isSafeInteger(args.nonce) || args.nonce < 0) throw new Error("INVALID_NONCE");
  if (!/^0x[0-9a-fA-F]{64}$/.test(args.txHash)) throw new Error("INVALID_TX_HASH");

  const rows = await db.select().from(executionIntents)
    .where(eq(executionIntents.actionKey, actionKey))
    .limit(1);
  const current = rows[0];
  if (!current) throw new Error("EXECUTION_INTENT_NOT_FOUND");
  if (current.status !== "prepared") throw new Error("EXECUTION_ALREADY_SUBMITTED");

  const result = await db.update(executionIntents).set({
    fromAddress: args.fromAddress.toLowerCase(),
    nonce: args.nonce,
    txHash: args.txHash.toLowerCase(),
    updatedAt: new Date(),
  }).where(and(
    eq(executionIntents.actionKey, actionKey),
    eq(executionIntents.status, "prepared"),
  ));
  if (result.meta.changes !== 1) throw new Error("EXECUTION_PREPARE_RACE");
}

export async function markExecution(
  env: Env,
  actionKey: string,
  status: ExecutionStatus,
  patch?: { txHash?: string; error?: string },
) {
  const db = drizzle(env.DB);
  const rows = await db.select().from(executionIntents)
    .where(eq(executionIntents.actionKey, actionKey))
    .limit(1);

  const current = rows[0];
  if (!current) throw new Error("EXECUTION_INTENT_NOT_FOUND");

  const allowed: Record<ExecutionStatus, ExecutionStatus[]> = {
    prepared: ["broadcast", "confirmed", "failed_before_broadcast", "failed_after_broadcast"],
    broadcast: ["confirmed", "failed_after_broadcast"],
    confirmed: [],
    failed_before_broadcast: [],
    failed_after_broadcast: [],
  };

  if (!allowed[current.status].includes(status)) {
    throw new Error("INVALID_EXECUTION_TRANSITION");
  }

  if ((status === "broadcast" || status === "confirmed" || status === "failed_after_broadcast") && !patch?.txHash && !current.txHash) {
    throw new Error("TX_HASH_REQUIRED");
  }

  if (patch?.txHash && !/^0x[0-9a-fA-F]{64}$/.test(patch.txHash)) {
    throw new Error("INVALID_TX_HASH");
  }

  const result = await db.update(executionIntents).set({
    status,
    txHash: patch?.txHash ?? current.txHash,
    error: patch?.error ?? current.error,
    updatedAt: new Date(),
  }).where(and(
    eq(executionIntents.actionKey, actionKey),
    eq(executionIntents.status, current.status),
  ));
  if (result.meta.changes !== 1) throw new Error("EXECUTION_TRANSITION_RACE");
}
