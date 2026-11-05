import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const page = readFileSync(resolve(process.cwd(), 'app/HomePageClient.tsx'), 'utf8');
const showcase = readFileSync(resolve(process.cwd(), 'components/LandingFeatureShowcase.tsx'), 'utf8');

describe('landing page experience', () => {
  it('uses the requested landing-page order and Iron starting rank', () => {
    const hero = page.indexOf('Play more.');
    const features = page.indexOf('id="features"');
    const rankJourney = page.indexOf('Your rank journey');
    const about = page.indexOf('id="about"');

    expect(hero).toBeGreaterThan(-1);
    expect(features).toBeGreaterThan(hero);
    expect(rankJourney).toBeGreaterThan(features);
    expect(about).toBeGreaterThan(rankJourney);
    expect(page).toContain('Starting rank');
    expect(page).toContain('>Iron</span>');
    expect(page).not.toContain('Starting ELO');
    expect(page).not.toContain('id="rules"');
  });

  it('keeps all interactive previews in a mobile snap carousel and desktop grid', () => {
    expect(showcase).toContain('<RankedDemo key="ranked" />');
    expect(showcase).toContain('<QueueDemo key="queue" />');
    expect(showcase).toContain('<LeaderboardDemo key="leaderboard" />');
    expect(showcase).toContain('snap-x snap-mandatory');
    expect(showcase).toContain('snap-center');
    expect(showcase).toContain('lg:grid lg:grid-cols-3');
    expect(showcase).toContain('aria-current={activeCard === index');
    expect(showcase).toContain('onClickCapture');
  });

  it('shows the board and external Instagram invitation', () => {
    for (const member of ['Iona', 'Almasur', 'Ethan', 'Mohammed']) expect(page).toContain(`name: '${member}'`);
    expect(page).toContain('<BeaverAvatar config={member.avatar}');
    expect(page).toContain('https://www.instagram.com/j/AbY5vus4CfKEHPGJ/');
    expect(page).toContain('target="_blank"');
    expect(page).toContain('rel="noopener noreferrer"');
  });
});
