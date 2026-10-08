import type { Metadata } from "next";
import { ElliquidApp } from "@/components/elliquid-app";

export const metadata: Metadata = {
  title: "Elliquid | Programmable liquidity for Elysium",
  description: "An introduction to Elliquid and its liquidity request, strategy, project, and protocol risk pages for Elysium.",
};

export default function Home() {
  return <ElliquidApp page="home" />;
}
