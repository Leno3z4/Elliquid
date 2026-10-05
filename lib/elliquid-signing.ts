import {
  buildTypedAction,
  ELLIQUID_EIP712_DOMAIN,
  ELLIQUID_EIP712_TYPES,
  getRequestHash,
} from "@elliquid/shared/signing";

export function createElliquidSignedAction(args: {
  action: string;
  endpoint: string;
  body: unknown;
  idempotencyKey?: string;
  timestamp?: number;
}) {
  const idempotencyKey = args.idempotencyKey ?? crypto.randomUUID();
  const timestamp = args.timestamp ?? Date.now();
  const requestHash = getRequestHash(args.endpoint, args.action, args.body);
  const message = buildTypedAction({
    action: args.action,
    endpoint: args.endpoint,
    idempotencyKey,
    requestHash,
    timestamp,
  });

  return {
    idempotencyKey,
    timestamp,
    requestHash,
    domain: ELLIQUID_EIP712_DOMAIN,
    types: ELLIQUID_EIP712_TYPES,
    primaryType: "ElliquidAction" as const,
    message,
  };
}
