import { keccak256, stringToHex } from "viem";

export const ELLIQUID_CHAIN_ID = 99801;

export const ELLIQUID_EIP712_DOMAIN = {
  name: "Elliquid API",
  version: "1",
  chainId: ELLIQUID_CHAIN_ID,
} as const;

export const ELLIQUID_EIP712_TYPES = {
  ElliquidAction: [
    { name: "action", type: "string" },
    { name: "endpoint", type: "string" },
    { name: "idempotencyKey", type: "string" },
    { name: "requestHash", type: "bytes32" },
    { name: "timestamp", type: "uint256" },
  ],
} as const;

function canonicalize(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonicalize).join(",") + "]";
  const record = value as Record<string, unknown>;
  return "{" + Object.keys(record).sort().map((key) => JSON.stringify(key) + ":" + canonicalize(record[key])).join(",") + "}";
}

export function getRequestHash(endpoint: string, action: string, body: unknown) {
  return keccak256(stringToHex(endpoint + "|" + action + "|" + canonicalize(body)));
}

export function buildTypedAction(args: {
  action: string;
  endpoint: string;
  idempotencyKey: string;
  requestHash: `0x${string}`;
  timestamp: number;
}) {
  return {
    action: args.action,
    endpoint: args.endpoint,
    idempotencyKey: args.idempotencyKey,
    requestHash: args.requestHash,
    timestamp: BigInt(args.timestamp),
  };
}
