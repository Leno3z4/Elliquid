INSERT OR IGNORE INTO strategies (
  id, name, slug, description, risk, target_apy,
  management_fee_bps, performance_fee_bps, active, created_at
) VALUES
  ('strategy-market-maker', 'Elysium Market Maker', 'elysium-market-maker',
   'Managed two-sided liquidity with inventory limits', 'medium', 18.4,
   100, 1000, 1, CAST(strftime('%s','now') AS INTEGER) * 1000),
  ('strategy-hype-carry', 'HYPE Carry', 'hype-carry',
   'HYPE-denominated liquidity with conservative hedging', 'low', 11.8,
   75, 750, 1, CAST(strftime('%s','now') AS INTEGER) * 1000),
  ('strategy-project-liquidity', 'Project Liquidity', 'project-liquidity',
   'Liquidity-as-a-service for vetted Elysium projects', 'high', 26.1,
   125, 1250, 1, CAST(strftime('%s','now') AS INTEGER) * 1000);
