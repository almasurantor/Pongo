import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Toaster } from "react-hot-toast";
import ConditionalNavbar from "@/components/ConditionalNavbar";
import PWAClient from "@/components/PWAClient";
import { ThemeProvider } from "@/components/ThemeProvider";
import NavigationFeedback from "@/components/NavigationFeedback";
import { Suspense } from "react";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  applicationName: "Pongo",
  title: {
    default: "Pongo",
    template: "%s · Pongo",
  },
  description: "Challenge players, track matches, and climb the table tennis ranks.",
  manifest: "/manifest.webmanifest",
  icons: {
    icon: [{ url: "/icon.png?v=4", type: "image/png", sizes: "512x512" }],
    apple: [{ url: "/apple-icon.png?v=4", type: "image/png", sizes: "180x180" }],
  },
  appleWebApp: {
    capable: true,
    title: "Pongo",
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
  colorScheme: "light dark",
  themeColor: "#2563EB",
};

const themeScript = `
  try {
    var saved = localStorage.getItem('beaversmash-theme');
    var automatic = saved !== 'light' && saved !== 'dark';
    var dark = saved === 'dark' || (automatic && matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.classList.toggle('dark', dark);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  } catch (_) {}
`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head><script dangerouslySetInnerHTML={{ __html: themeScript }} /></head>
      <body className={inter.className} suppressHydrationWarning>
        <ThemeProvider>
          <PWAClient />
          <Suspense fallback={null}><NavigationFeedback /></Suspense>
          <ConditionalNavbar />
          {children}
          <Toaster
            position="top-right"
            toastOptions={{
              style: {
                background: '#FFFFFF',
                color: '#0F172A',
                border: '2px solid #2563EB',
                borderRadius: '12px',
                boxShadow: '0 10px 25px rgba(37, 99, 235, 0.2)',
              },
              className: 'theme-toast',
              success: {
                iconTheme: {
                  primary: '#2563EB',
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
        </ThemeProvider>
      </body>
    </html>
  );
}
