import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/providers";

export const metadata: Metadata = {
  title: "Elliquid | Programmable liquidity for Elysium",
  description: "Review Elysium liquidity requests, configured strategies, project records, and documented protocol limits.",
  icons: { icon: "data:," },
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
