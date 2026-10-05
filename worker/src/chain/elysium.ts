import { createPublicClient, http } from "viem";
import { defineChain } from "viem/utils";
import type { Env } from "../env";

export const ELYSIUM_TESTNET = defineChain({
  id: 99801,
  name: "Elysium Testnet",
  nativeCurrency: {
    name: "HYPE",
    symbol: "HYPE",
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ["https://testnet-rpc.elysium.kinetiq.xyz"],
    },
  },
});

export function getElysiumClient(env: Env) {
  return createPublicClient({
    chain: ELYSIUM_TESTNET,
    transport: http(env.ELYSIUM_RPC_URL || ELYSIUM_TESTNET.rpcUrls.default.http[0]),
  });
}
