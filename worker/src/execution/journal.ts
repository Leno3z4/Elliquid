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
  args: { actionKey: string; vaultId?: string; action: string },
) {
  const db = drizzle(env.DB);
  const now = new Date();

  const inserted = await db.insert(executionIntents).values({
    actionKey: args.actionKey,
    vaultId: args.vaultId,
    action: args.action,
    status: "prepared",
    createdAt: now,
    updatedAt: now,
  }).onConflictDoNothing();

  if (inserted.rowsAffected === 1) {
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

export async function markExecution(
  env: Env,
  actionKey: string,
  status: ExecutionStatus,
  patch?: { txHash?: string; error?: string },
) {
  const db = drizzle(env.DB);
  const rows = await db.select().from(executionIntents)
    .where(and(
      eq(executionIntents.actionKey, actionKey),
    ))
    .limit(1);

  if (!rows[0]) throw new Error("EXECUTION_INTENT_NOT_FOUND");

  await db.update(executionIntents).set({
    status,
    txHash: patch?.txHash ?? rows[0].txHash,
    error: patch?.error ?? rows[0].error,
    updatedAt: new Date(),
  }).where(eq(executionIntents.actionKey, actionKey));
}
