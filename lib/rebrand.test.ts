import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const packageJson = JSON.parse(readFileSync(resolve(process.cwd(), 'package.json'), 'utf8')) as { name: string };
const layout = readFileSync(resolve(process.cwd(), 'app/layout.tsx'), 'utf8');
const manifest = readFileSync(resolve(process.cwd(), 'app/manifest.ts'), 'utf8');
const theme = readFileSync(resolve(process.cwd(), 'components/ThemeProvider.tsx'), 'utf8');
const installHint = readFileSync(resolve(process.cwd(), 'components/InstallAppHint.tsx'), 'utf8');

describe('Pongo rebrand', () => {
  it('uses Pongo for package and installable-app metadata', () => {
    expect(packageJson.name).toBe('pongo');
    expect(layout).toContain('applicationName: "Pongo"');
    expect(layout).toContain('appleWebApp');
    expect(layout).toContain('siteName: "Pongo"');
    expect(layout).toContain('getSiteUrl');
    expect(layout).toContain('alternates: { canonical: "/" }');
    expect(manifest).toContain("name: 'Pongo'");
    expect(manifest).toContain("short_name: 'Pongo'");
    expect(existsSync(resolve(process.cwd(), 'app/opengraph-image.png'))).toBe(true);
    expect(existsSync(resolve(process.cwd(), 'app/twitter-image.png'))).toBe(true);
  });

  it('uses the Pongo production URL for metadata discovery files', () => {
    const siteUrl = readFileSync(resolve(process.cwd(), 'lib/site-url.ts'), 'utf8');
    const sitemap = readFileSync(resolve(process.cwd(), 'app/sitemap.ts'), 'utf8');
    const robots = readFileSync(resolve(process.cwd(), 'app/robots.ts'), 'utf8');
    expect(siteUrl).toContain("https://playpongo.vercel.app");
    expect(sitemap).toContain("new URL('/', siteUrl)");
    expect(robots).toContain("'/sitemap.xml'");
  });

  it('migrates legacy local preferences to Pongo keys', () => {
    expect(theme).toContain("const STORAGE_KEY = 'pongo-theme'");
    expect(theme).toContain('LEGACY_STORAGE_KEY');
    expect(installHint).toContain("const INSTALL_HINT_KEY = 'pongo-install-hint-dismissed'");
    expect(installHint).toContain('LEGACY_INSTALL_HINT_KEY');
    expect(installHint).toContain('id="install-pongo"');
  });
});
