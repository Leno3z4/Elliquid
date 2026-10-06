import { eq } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import {
  encodeFunctionData,
  getAddress,
  keccak256,
  parseEventLogs,
  stringToHex,
  type Address,
  type Hex,
} from "viem";
import { liquidityRequests, projects, vaults, executionIntents } from "../db/schema";
import type { Env } from "../env";
import {
  getElysiumClient,
  getElysiumWalletClient,
  getExecutionAccount,
} from "../chain/elysium";
import { marketplaceAbi, vaultAbi } from "../chain/abis";
import {
  claimExecution,
  markExecution,
  prepareExecution,
} from "./journal";

function asAddress(value: string, label: string): Address {
  try {
    return getAddress(value);
  } catch {
    throw new Error("INVALID_" + label.toUpperCase() + "_ADDRESS");
  }
}

function actionKey(seed: string): Hex {
  return keccak256(stringToHex(seed));
}

async function getIntent(env: Env, actionKeyValue: string) {
  const db = drizzle(env.DB);
  const rows = await db.select().from(executionIntents)
    .where(eq(executionIntents.actionKey, actionKeyValue))
    .limit(1);
  return rows[0];
}

async function tryReconcile(env: Env, actionKeyValue: string) {
  const intent = await getIntent(env, actionKeyValue);
  if (!intent) throw new Error("EXECUTION_INTENT_NOT_FOUND");
  if (!intent.txHash) return { state: "prepared" as const, txHash: intent.txHash, intent };

  try {
    const receipt = await getElysiumClient(env).getTransactionReceipt({
      hash: intent.txHash as Hex,
    });
    if (receipt.status === "success") {
      if (intent.status === "prepared" || intent.status === "broadcast") {
        await markExecution(env, actionKeyValue, "confirmed", {
          txHash: intent.txHash,
        });
      }
      return { state: "confirmed" as const, txHash: intent.txHash, receipt, intent };
    }

    if (intent.status === "prepared" || intent.status === "broadcast") {
      await markExecution(
        env,
        actionKeyValue,
        "failed_after_broadcast",
        { txHash: intent.txHash, error: "TRANSACTION_REVERTED" },
      );
    }
    return { state: "failed" as const, txHash: intent.txHash, receipt, intent };
  } catch {
    return { state: "pending" as const, txHash: intent.txHash, intent };
  }
}

async function submitRawContractCall(env: Env, args: {
  actionKey: Hex;
  action: string;
  vaultId?: string;
  to: Address;
  data: Hex;
  value?: bigint;
}) {
  const existing = await claimExecution(env, {
    actionKey: args.actionKey,
    vaultId: args.vaultId,
    action: args.action,
  });

  if (existing.state === "conflict") throw new Error("EXECUTION_KEY_CONFLICT");
  if (existing.state === "missing") throw new Error("EXECUTION_INTENT_MISSING");

  if (existing.state === "existing") {
    if (
      existing.row.status === "confirmed" ||
      existing.row.status === "failed_before_broadcast" ||
      existing.row.status === "failed_after_broadcast"
    ) {
      return {
        state: existing.row.status,
        txHash: existing.row.txHash,
      };
    }

    if (existing.row.status === "broadcast") {
      return await tryReconcile(env, args.actionKey);
    }

    if (existing.row.status === "prepared" && existing.row.txHash) {
      const reconciled = await tryReconcile(env, args.actionKey);
      if (reconciled.state !== "pending") return reconciled;
    }
  }

  const publicClient = getElysiumClient(env);
  const walletClient = getElysiumWalletClient(env);
  const account = getExecutionAccount(env);

  const nonce =
    existing.state === "existing" && existing.row.nonce !== null
      ? existing.row.nonce
      : await publicClient.getTransactionCount({
          address: account.address,
          blockTag: "pending",
        });

  await publicClient.call({
    account: account.address,
    to: args.to,
    data: args.data,
    value: args.value ?? 0n,
  });

  const request = await walletClient.prepareTransactionRequest({
    account: account.address,
    to: args.to,
    data: args.data,
    value: args.value ?? 0n,
    nonce,
  });

  const raw = await walletClient.signTransaction(request);
  const txHash = keccak256(raw) as Hex;

  await prepareExecution(env, args.actionKey, {
    fromAddress: account.address,
    nonce,
    txHash,
  });

  try {
    const sent = await walletClient.sendRawTransaction({
      serializedTransaction: raw,
    });

    if (sent.toLowerCase() !== txHash.toLowerCase()) {
      throw new Error("TX_HASH_MISMATCH");
    }

    await markExecution(env, args.actionKey, "broadcast", { txHash });
    return { state: "broadcast" as const, txHash };
  } catch {
    const reconciled = await tryReconcile(env, args.actionKey);
    if (reconciled.state === "confirmed" || reconciled.state === "failed") {
      return {
        state: reconciled.state,
        txHash,
      };
    }

    // Do not mark failed and do not generate a new nonce. The prepared record
    // already contains the sender, nonce and expected hash, so recovery can
    // safely use the same nonce instead of creating a second on-chain action.
    throw new Error("TX_SUBMISSION_UNCERTAIN");
  }
}

export async function reconcileExecution(env: Env, actionKeyValue: string) {
  if (!/^0x[0-9a-fA-F]{64}$/.test(actionKeyValue)) {
    throw new Error("INVALID_ACTION_KEY");
  }
  return tryReconcile(env, actionKeyValue);
}

function requireExecutor(env: Env, suppliedWallet?: string) {
  const account = getExecutionAccount(env);
  if (suppliedWallet && suppliedWallet.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error("EXECUTOR_SIGNATURE_REQUIRED");
  }
  return account;
}

export async function createOnchainRequest(env: Env, requestId: string) {
  const db = drizzle(env.DB);
  const rows = await db.select().from(liquidityRequests)
    .where(eq(liquidityRequests.id, requestId))
    .limit(1);
  const request = rows[0];
  if (!request) throw new Error("LIQUIDITY_REQUEST_NOT_FOUND");
  if (request.onchainRequestId !== null) {
    return { state: "existing" as const, request };
  }

  const projectRows = await db.select().from(projects)
    .where(eq(projects.id, request.projectId))
    .limit(1);
  const project = projectRows[0];
  if (!project) throw new Error("PROJECT_NOT_FOUND");

  const marketplace = asAddress(env.MARKETPLACE_ADDRESS ?? "", "marketplace");
  const account = getExecutionAccount(env);
  const publicClient = getElysiumClient(env);
  const operator = await publicClient.readContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "operator",
  });
  if (operator.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error("MARKETPLACE_OPERATOR_MISMATCH");
  }

  const requestKey = actionKey(
    project.wallet.toLowerCase() + ":" + request.id,
  );
  const data = encodeFunctionData({
    abi: marketplaceAbi,
    functionName: "createRequestFor",
    args: [
      asAddress(project.wallet, "project"),
      requestKey,
      asAddress(project.baseToken, "base_token"),
      asAddress(project.quoteToken, "quote_token"),
      BigInt(request.targetQuote),
      BigInt(request.durationSeconds),
      request.maxInventoryBps,
      request.liquidityFeeBps,
    ],
  });

  const executionKey = actionKey("marketplace-create:" + request.id);
  const result = await submitRawContractCall(env, {
    actionKey: executionKey,
    action: executionKey,
    to: marketplace,
    data,
  });

  if (result.txHash) {
    await db.update(liquidityRequests)
      .set({ lastTxHash: result.txHash })
      .where(eq(liquidityRequests.id, request.id));
  }

  if (result.state === "confirmed") {
    const reconciled = await tryReconcile(env, executionKey);
    if (reconciled.state === "confirmed" && reconciled.receipt) {
      const logs = parseEventLogs({
        abi: marketplaceAbi,
        eventName: "RequestCreated",
        logs: reconciled.receipt.logs,
      });
      const onchainId = logs[0]?.args.id;
      if (onchainId === undefined) {
        throw new Error("REQUEST_CREATED_EVENT_MISSING");
      }
      await db.update(liquidityRequests).set({
        onchainRequestId: Number(onchainId),
        lastTxHash: result.txHash,
      }).where(eq(liquidityRequests.id, request.id));
    }
  }

  return result;
}

export async function fillOnchainRequest(
  env: Env,
  requestId: string,
  signedWallet?: string,
) {
  requireExecutor(env, signedWallet);

  const db = drizzle(env.DB);
  const rows = await db.select().from(liquidityRequests)
    .where(eq(liquidityRequests.id, requestId))
    .limit(1);
  const request = rows[0];

  if (!request || request.onchainRequestId === null) {
    throw new Error("ONCHAIN_REQUEST_NOT_READY");
  }

  const marketplace = asAddress(env.MARKETPLACE_ADDRESS ?? "", "marketplace");
  const account = getExecutionAccount(env);
  const publicClient = getElysiumClient(env);
  const operator = await publicClient.readContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "operator",
  });
  if (operator.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error("MARKETPLACE_OPERATOR_MISMATCH");
  }

  const executionKey = actionKey(
    "marketplace-fill:" + String(request.onchainRequestId),
  );
  const data = encodeFunctionData({
    abi: marketplaceAbi,
    functionName: "fillRequest",
    args: [BigInt(request.onchainRequestId)],
  });

  const result = await submitRawContractCall(env, {
    actionKey: executionKey,
    action: executionKey,
    to: marketplace,
    data,
  });

  if (result.txHash) {
    await db.update(liquidityRequests)
      .set({ lastTxHash: result.txHash })
      .where(eq(liquidityRequests.id, request.id));
  }

  if (result.state === "confirmed") {
    await db.update(liquidityRequests)
      .set({ status: "filled" })
      .where(eq(liquidityRequests.id, request.id));
  }

  return result;
}

export async function executeVaultAdapter(
  env: Env,
  args: {
    requestId: string;
    vaultId: string;
    assetsToFund: string;
    adapterData: Hex;
    signedWallet?: string;
  },
) {
  requireExecutor(env, args.signedWallet);

  const db = drizzle(env.DB);
  const requestRows = await db.select().from(liquidityRequests)
    .where(eq(liquidityRequests.id, args.requestId))
    .limit(1);
  const request = requestRows[0];

  if (!request || request.status !== "filled") {
    throw new Error("REQUEST_NOT_FILLED");
  }

  const vaultRows = await db.select().from(vaults)
    .where(eq(vaults.id, args.vaultId))
    .limit(1);
  const vault = vaultRows[0];

  if (!vault || !vault.active || !vault.contractAddress ||
      !vault.adapterAddress || !vault.assetAddress) {
    throw new Error("VAULT_EXECUTION_CONFIG_MISSING");
  }

  if (vault.strategyId !== request.strategyId) {
    throw new Error("VAULT_STRATEGY_MISMATCH");
  }

  const projectRows = await db.select().from(projects)
    .where(eq(projects.id, request.projectId))
    .limit(1);
  const project = projectRows[0];
  if (!project) throw new Error("PROJECT_NOT_FOUND");

  if (vault.assetAddress.toLowerCase() !== project.baseToken.toLowerCase()) {
    throw new Error("VAULT_ASSET_MISMATCH");
  }

  if (!/^\d+$/.test(args.assetsToFund) || BigInt(args.assetsToFund) <= 0n) {
    throw new Error("INVALID_ASSETS_TO_FUND");
  }

  if (!/^0x[0-9a-fA-F]*$/.test(args.adapterData) ||
      args.adapterData.length > 32768) {
    throw new Error("INVALID_ADAPTER_DATA");
  }

  const account = getExecutionAccount(env);
  const publicClient = getElysiumClient(env);
  const vaultAddress = asAddress(vault.contractAddress, "vault");
  const adapter = asAddress(vault.adapterAddress, "adapter");

  const [executor, allowed, onchainAsset] = await Promise.all([
    publicClient.readContract({
      address: vaultAddress,
      abi: vaultAbi,
      functionName: "strategyExecutor",
    }),
    publicClient.readContract({
      address: vaultAddress,
      abi: vaultAbi,
      functionName: "approvedAdapters",
      args: [adapter],
    }),
    publicClient.readContract({
      address: vaultAddress,
      abi: vaultAbi,
      functionName: "asset",
    }),
  ]);

  if (executor.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error("VAULT_EXECUTOR_MISMATCH");
  }
  if (!allowed) throw new Error("ADAPTER_NOT_APPROVED");
  if (onchainAsset.toLowerCase() !== vault.assetAddress.toLowerCase()) {
    throw new Error("VAULT_CHAIN_ASSET_MISMATCH");
  }

  const amount = BigInt(args.assetsToFund);
  const executionKey = actionKey(
    "vault-adapter:" +
      request.id +
      ":" +
      vault.id +
      ":" +
      keccak256(args.adapterData),
  );

  const data = encodeFunctionData({
    abi: vaultAbi,
    functionName: "executeAdapter",
    args: [executionKey, adapter, amount, args.adapterData],
  });

  const result = await submitRawContractCall(env, {
    actionKey: executionKey,
    action: executionKey,
    vaultId: vault.id,
    to: vaultAddress,
    data,
  });

  if (result.txHash) {
    await db.update(liquidityRequests)
      .set({ lastTxHash: result.txHash })
      .where(eq(liquidityRequests.id, request.id));
  }

  return result;
}
