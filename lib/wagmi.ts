import { defineChain, http } from "viem";
import { createConfig, injected } from "wagmi";

export const elysiumTestnet = defineChain({
  id: 99801,
  name: "Elysium Testnet",
  nativeCurrency: {
    decimals: 18,
    name: "HYPE",
    symbol: "HYPE",
  },
  rpcUrls: {
    default: {
      http: ["https://testnet-rpc.elysium.kinetiq.xyz"],
    },
  },
  testnet: true,
});

export const wagmiConfig = createConfig({
  chains: [elysiumTestnet],
  connectors: [injected()],
  transports: {
    [elysiumTestnet.id]: http(),
  },
  ssr: true,
});
