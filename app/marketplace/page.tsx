import type { Metadata } from "next";
import { ElliquidApp } from "@/components/elliquid-app";

export const metadata: Metadata = {
  title: "Liquidity requests | Elliquid",
  description: "Review recorded Elysium liquidity request terms, status, duration, fee, and inventory limits.",
};

export default function MarketplacePage() {
  return <ElliquidApp page="marketplace" />;
}
