import type { Metadata } from "next";
import { ElliquidApp } from "@/components/elliquid-app";

export const metadata: Metadata = {
  title: "Risk and protocol limits | Elliquid",
  description: "Read Elliquid's documented controls, current testnet status, and known protocol limitations.",
};

export default function RiskPage() {
  return <ElliquidApp page="risk" />;
}
