export const ELYSIUM_TESTNET = {
  chainId: 99801,
  name: "Elysium Testnet",
  rpcUrl: "https://testnet-rpc.elysium.kinetiq.xyz",
};

export function shortAddress(address: string) {
  return address.slice(0, 6) + "…" + address.slice(-4);
}
