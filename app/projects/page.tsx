import type { Metadata } from "next";
import { ElliquidApp } from "@/components/elliquid-app";

export const metadata: Metadata = {
  title: "Projects | Elliquid",
  description: "Review Elysium project token pairs and verification states returned by the configured API.",
};

export default function ProjectsPage() {
  return <ElliquidApp page="projects" />;
}
