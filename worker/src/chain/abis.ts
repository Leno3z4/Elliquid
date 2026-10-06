import type { Abi } from "viem";

export const marketplaceAbi = [
  { type: "function", name: "operator", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  {
    type: "function",
    name: "createRequestFor",
    stateMutability: "nonpayable",
    inputs: [
      { name: "creator", type: "address" },
      { name: "requestKey", type: "bytes32" },
      { name: "baseToken", type: "address" },
      { name: "quoteToken", type: "address" },
      { name: "targetQuote", type: "uint256" },
      { name: "durationSeconds", type: "uint64" },
      { name: "inventoryCapBps", type: "uint16" },
      { name: "liquidityFeeBps", type: "uint16" }
    ],
    outputs: [{ type: "uint256" }]
  },
  { type: "function", name: "fillRequest", stateMutability: "nonpayable", inputs: [{ name: "id", type: "uint256" }], outputs: [] },
  {
    type: "event",
    name: "RequestCreated",
    anonymous: false,
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "creator", type: "address", indexed: true },
      { name: "requestKey", type: "bytes32", indexed: true },
      { name: "baseToken", type: "address", indexed: false },
      { name: "quoteToken", type: "address", indexed: false },
      { name: "targetQuote", type: "uint256", indexed: false }
    ]
  }
] as const satisfies Abi;

export const vaultAbi = [
  { type: "function", name: "strategyExecutor", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "approvedAdapters", stateMutability: "view", inputs: [{ name: "", type: "address" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "asset", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "maxAdapterFundingBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "executeAdapter",
    stateMutability: "nonpayable",
    inputs: [
      { name: "actionKey", type: "bytes32" },
      { name: "adapter", type: "address" },
      { name: "assetsToFund", type: "uint256" },
      { name: "data", type: "bytes" }
    ],
    outputs: [{ type: "bytes" }]
  }
] as const satisfies Abi;
