import { integer, real, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const strategies = sqliteTable("strategies", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  description: text("description").notNull(),
  risk: text("risk", { enum: ["low", "medium", "high"] }).notNull(),
  targetApy: real("target_apy"),
  managementFeeBps: integer("management_fee_bps").notNull().default(0),
  performanceFeeBps: integer("performance_fee_bps").notNull().default(0),
  active: integer("active", { mode: "boolean" }).notNull().default(true),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const projects = sqliteTable("projects", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  wallet: text("wallet").notNull(),
  baseToken: text("base_token").notNull(),
  quoteToken: text("quote_token").notNull(),
  verified: integer("verified", { mode: "boolean" }).notNull().default(false),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const liquidityRequests = sqliteTable("liquidity_requests", {
  id: text("id").primaryKey(),
  projectId: text("project_id").notNull().references(() => projects.id),
  strategyId: text("strategy_id").notNull().references(() => strategies.id),
  targetQuote: text("target_quote").notNull(),
  durationSeconds: integer("duration_seconds").notNull(),
  maxInventoryBps: integer("max_inventory_bps").notNull(),
  liquidityFeeBps: integer("liquidity_fee_bps").notNull(),
  status: text("status", { enum: ["open", "filled", "cancelled", "expired"] }).notNull().default("open"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const vaults = sqliteTable("vaults", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  strategyId: text("strategy_id").notNull().references(() => strategies.id),
  assetSymbol: text("asset_symbol").notNull(),
  chainId: integer("chain_id").notNull(),
  contractAddress: text("contract_address"),
  tvl: text("tvl").notNull().default("0"),
  active: integer("active", { mode: "boolean" }).notNull().default(false),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const executionEvents = sqliteTable("execution_events", {
  id: text("id").primaryKey(),
  vaultId: text("vault_id").references(() => vaults.id),
  eventType: text("event_type").notNull(),
  txHash: text("tx_hash"),
  payload: text("payload").notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const idempotencyKeys = sqliteTable("idempotency_keys", {
  wallet: text("wallet").notNull(),
  key: text("key").notNull(),
  endpoint: text("endpoint").notNull(),
  requestHash: text("request_hash").notNull(),
  status: text("status", { enum: ["processing", "completed"] }).notNull().default("processing"),
  responseStatus: integer("response_status"),
  responseBody: text("response_body"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
});
