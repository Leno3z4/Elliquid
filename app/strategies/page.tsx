import type { Metadata } from "next";
import { ElliquidApp } from "@/components/elliquid-app";

export const metadata: Metadata = {
  title: "Strategies | Elliquid",
  description: "Review configured strategy descriptions, activity status, and stated risk categories.",
};

export default function StrategiesPage() {
  return <ElliquidApp page="strategies" />;
}
