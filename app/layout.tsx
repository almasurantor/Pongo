import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Toaster } from "react-hot-toast";
import ConditionalNavbar from "@/components/ConditionalNavbar";
import PWAClient from "@/components/PWAClient";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  applicationName: "Beaver Smash",
  title: {
    default: "Beaver Smash",
    template: "%s · Beaver Smash",
  },
  description: "A competitive table tennis ranking and match-tracking app for the CCNY Table Tennis Club.",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    title: "Beaver Smash",
    statusBarStyle: "black-translucent",
  },
  other: {
    "mobile-web-app-capable": "yes",
  },
  formatDetection: {
    telephone: false,
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  colorScheme: "light",
  themeColor: "#5B21B6",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={inter.className} suppressHydrationWarning>
        <PWAClient />
        <ConditionalNavbar />
        {children}
        <Toaster 
          position="top-right"
          toastOptions={{
            style: {
              background: '#FFFFFF',
              color: '#000000',
              border: '2px solid #7C3AED',
              borderRadius: '12px',
              boxShadow: '0 10px 25px rgba(124, 58, 237, 0.2)',
            },
            success: {
              iconTheme: {
                primary: '#7C3AED',
                secondary: '#fff',
              },
            },
            error: {
              iconTheme: {
                primary: '#EF4444',
                secondary: '#fff',
              },
            },
          }}
        />
      </body>
    </html>
  );
}
