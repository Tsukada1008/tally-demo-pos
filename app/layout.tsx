import type { Metadata, Viewport } from "next";
import "./globals.css";
import "./workflow.css";
import "./catalog-settings.css";
import "./staff-drink.css";
import "./table-info.css";
import "./qr.css";
import "./settings-dialog.css";
import "./mobile-order.css";
import "./auth/auth.css";
import "./simple-theme.css";

const appEnv = process.env.NEXT_PUBLIC_APP_ENV; // "demo" | "sample" | undefined (production)
const titleTag = appEnv === "demo" ? "【DEMO】" : appEnv === "sample" ? "【SAMPLE】" : "";
const appName = appEnv === "demo" ? "Tally" : "TIPSY";
const descTag = appEnv === "demo" ? "（フル機能デモ環境）" : appEnv === "sample" ? "（データなしサンプル環境）" : "";

export const metadata: Metadata = {
  title: `${titleTag}${appName} CHECK | 会計・伝票管理`,
  description: "バー専用 会計・伝票管理Webアプリ" + descTag
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover"
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ja"><body>{children}</body></html>;
}
