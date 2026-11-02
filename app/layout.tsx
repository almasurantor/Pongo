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
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#5B21B6" },
    { media: "(prefers-color-scheme: dark)", color: "#171321" },
  ],
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
                color: '#000000',
                border: '2px solid #7C3AED',
                borderRadius: '12px',
                boxShadow: '0 10px 25px rgba(124, 58, 237, 0.2)',
              },
              className: 'theme-toast',
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
        </ThemeProvider>
      </body>
    </html>
  );
}
