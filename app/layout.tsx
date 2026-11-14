import type { Metadata, Viewport } from "next";
import PwaInstall from "./PwaInstall";
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
  description: "バー専用 会計・伝票管理Webアプリ" + descTag,
  applicationName: `${appName} CHECK`,
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    title: `${appName} CHECK`,
    statusBarStyle: "black-translucent"
  },
  icons: {
    icon: [
      {url: "/icons/icon-192.png",sizes: "192x192",type: "image/png"},
      {url: "/icons/icon-512.png",sizes: "512x512",type: "image/png"}
    ],
    apple: [{url: "/icons/apple-touch-icon.png",sizes: "180x180",type: "image/png"}]
  }
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#151719"
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ja"><body>{children}<PwaInstall/></body></html>;
}
