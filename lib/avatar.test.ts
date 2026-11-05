import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { avatarOptions, defaultAvatarConfig, normalizeAvatarConfig, randomAvatarConfig } from './avatar';

describe('Pongo avatar configuration', () => {
  it('uses recognizable Pongo defaults for missing or invalid data', () => {
    expect(normalizeAvatarConfig(null)).toEqual(defaultAvatarConfig);
    expect(normalizeAvatarConfig({ fur: 'invisible', hat: 'crown' })).toEqual({
      ...defaultAvatarConfig,
      hat: 'crown',
    });
  });

  it('keeps a valid structured configuration intact', () => {
    const config = {
      version: 1 as const,
      fur: 'blue' as const,
      hat: 'beanie' as const,
      glasses: 'round' as const,
      facialHair: 'mustache' as const,
      expression: 'mischievous' as const,
      accessory: 'headphones' as const,
    };
    expect(normalizeAvatarConfig(config)).toEqual(config);
  });

  it('randomizes only to supported layer values', () => {
    vi.spyOn(Math, 'random').mockReturnValue(0.999);
    const config = randomAvatarConfig();
    expect(avatarOptions.fur).toContain(config.fur);
    expect(avatarOptions.hat).toContain(config.hat);
    expect(avatarOptions.glasses).toContain(config.glasses);
    expect(avatarOptions.facialHair).toContain(config.facialHair);
    expect(avatarOptions.expression).toContain(config.expression);
    expect(avatarOptions.accessory).toContain(config.accessory);
    vi.restoreAllMocks();
  });

  it('renders the original Pongo artwork untouched for the default fur', () => {
    const renderer = readFileSync(join(process.cwd(), 'components/BeaverAvatar.tsx'), 'utf8');
    expect(renderer).toContain('href="/pongo.webp"');
    expect(renderer).toContain("avatar.fur === 'brown' ? undefined");
    expect(defaultAvatarConfig).toMatchObject({
      fur: 'brown', expression: 'happy', hat: 'none', glasses: 'none', facialHair: 'none', accessory: 'none',
    });
  });
});
