import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');
const navbar = read('components/Navbar.tsx');
const styles = read('app/globals.css');
const callback = read('app/auth/callback/route.ts');

describe('primary navigation', () => {
  it('orders Queue, Leaderboard, Home, Play, and Profile with Home emphasized', () => {
    const labels = ["label: 'Queue'", "label: 'Leaderboard'", "label: 'Home'", "label: 'Play'", "label: 'Profile'"];
    const positions = labels.map((label) => navbar.indexOf(label));
    expect(positions.every((position) => position >= 0)).toBe(true);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
    expect(navbar).toContain("{ href: '/dashboard', label: 'Home', icon: 'home', primary: true }");
    expect(navbar).toContain("item.label === 'Queue' && queueCalled");
    expect(navbar).not.toContain("label: 'Play', icon: 'play', primary: true");
  });

  it('uses a solid, safe-area-aware mobile bar without blur or shadow', () => {
    const mobileStyles = styles.slice(styles.indexOf('  .mobile-bottom-nav {'), styles.indexOf('.result-popup-backdrop'));
    expect(mobileStyles).toContain('padding-bottom: env(safe-area-inset-bottom)');
    expect(mobileStyles).toContain('background: #FFFFFF');
    expect(mobileStyles).toContain('background: #0B1120');
    expect(mobileStyles).not.toContain('backdrop-filter');
    expect(mobileStyles).not.toContain('box-shadow');
    expect(mobileStyles).not.toContain('rgba(');
    expect(mobileStyles).not.toContain('background: transparent');
  });

  it('defaults completed auth callbacks to the queue', () => {
    expect(callback).toContain("? requestedNext : '/queue'");
  });
});
