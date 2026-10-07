import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/providers";

export const metadata: Metadata = {
  title: "Elliquid: Programmable liquidity for Elysium",
  icons: { icon: "data:," },
  description: "Explore strategy-led liquidity for the Elysium ecosystem, with transparent project data and protocol-level risk controls.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
