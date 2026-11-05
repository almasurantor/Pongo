import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Toaster } from "react-hot-toast";
import ConditionalNavbar from "@/components/ConditionalNavbar";
import PWAClient from "@/components/PWAClient";
import { ThemeProvider } from "@/components/ThemeProvider";
import NavigationFeedback from "@/components/NavigationFeedback";
import { Suspense } from "react";
import AppResumeRedirect from "@/components/AppResumeRedirect";
import { getSiteUrl } from "@/lib/site-url";

export const metadata: Metadata = {
  metadataBase: getSiteUrl(),
  applicationName: "Pongo",
  title: {
    default: "Pongo",
    template: "%s · Pongo",
  },
  description: "Pongo helps CCNY students challenge players, track matches, and climb the table tennis ranks.",
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
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    siteName: "Pongo",
    url: "/",
    title: "Pongo",
    description: "The CCNY Table Tennis Club ladder, live queue, and match-day app.",
  },
  twitter: {
    card: "summary",
    title: "Pongo",
    description: "The CCNY Table Tennis Club ladder, live queue, and match-day app.",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F8FAFC" },
    { media: "(prefers-color-scheme: dark)", color: "#0B1120" },
  ],
};

const themeScript = `
  try {
    var saved = localStorage.getItem('pongo-theme') || localStorage.getItem('beaversmash-theme');
    if (saved === 'light' || saved === 'dark') localStorage.setItem('pongo-theme', saved);
    localStorage.removeItem('beaversmash-theme');
    var automatic = saved !== 'light' && saved !== 'dark';
    var dark = saved === 'dark' || (automatic && matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.classList.toggle('dark', dark);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    document.documentElement.style.backgroundColor = dark ? '#0B1120' : '#F8FAFC';
    var themeMeta = document.createElement('meta');
    themeMeta.name = 'theme-color';
    themeMeta.content = dark ? '#0B1120' : '#F8FAFC';
    themeMeta.dataset.pongoRuntime = 'true';
    document.head.appendChild(themeMeta);
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
      <body className="font-sans" suppressHydrationWarning>
        <ThemeProvider>
          <PWAClient />
          <Suspense fallback={null}><NavigationFeedback /></Suspense>
          <AppResumeRedirect />
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
