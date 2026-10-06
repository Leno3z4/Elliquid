const rpcUrl = process.env.NEXT_PUBLIC_ELYSIUM_RPC_URL?.trim() || "https://testnet-rpc.elysium.kinetiq.xyz";

export const ELYSIUM_TESTNET = {
  chainId: 99801,
  name: "Elysium Testnet",
  rpcUrl,
};

export function shortAddress(address: string) {
  return address.slice(0, 6) + "…" + address.slice(-4);
}
