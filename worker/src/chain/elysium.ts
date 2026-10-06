import { createPublicClient, createWalletClient, http } from "viem";
import { defineChain } from "viem/utils";
import { privateKeyToAccount } from "viem/accounts";
import type { Env } from "../env";

export const ELYSIUM_TESTNET = defineChain({
  id: 99801,
  name: "Elysium Testnet",
  testnet: true,
  nativeCurrency: { name: "HYPE", symbol: "HYPE", decimals: 18 },
  rpcUrls: { default: { http: ["https://testnet-rpc.elysium.kinetiq.xyz"] } },
  blockExplorers: {
    default: {
      name: "Elysium Explorer",
      url: "https://elysium.kinetiq.xyz/testnet-explorer",
    },
  },
});

export function getElysiumClient(env: Env) {
  return createPublicClient({
    chain: ELYSIUM_TESTNET,
    transport: http(env.ELYSIUM_RPC_URL || ELYSIUM_TESTNET.rpcUrls.default.http[0]),
  });
}

export function getExecutionAccount(env: Env) {
  const key = env.EXECUTOR_PRIVATE_KEY?.trim();
  if (!key || !/^0x[0-9a-fA-F]{64}$/.test(key)) {
    throw new Error("EXECUTOR_PRIVATE_KEY_NOT_CONFIGURED");
  }
  const account = privateKeyToAccount(key as `0x${string}`);
  if (env.EXECUTOR_ADDRESS && account.address.toLowerCase() !== env.EXECUTOR_ADDRESS.toLowerCase()) {
    throw new Error("EXECUTOR_ADDRESS_MISMATCH");
  }
  return account;
}

export function getElysiumWalletClient(env: Env) {
  const account = getExecutionAccount(env);
  return createWalletClient({
    account,
    chain: ELYSIUM_TESTNET,
    transport: http(env.ELYSIUM_RPC_URL || ELYSIUM_TESTNET.rpcUrls.default.http[0]),
  });
}
