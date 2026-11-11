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

  it('offers the intended choices, including the requested novelty options', () => {
    for (const [category, options] of Object.entries(avatarOptions)) {
      expect(options).toHaveLength(category === 'expression' ? 4 : 8);
    }
    expect(avatarOptions.fur).toContain('rainbow');
    expect(avatarOptions.hat).toContain('dickhead-hat');
    expect(avatarOptions.expression).toContain('angry');
    expect(avatarOptions.expression).not.toContain('big-smile');
    expect(avatarOptions.expression).not.toContain('surprised');
    expect(avatarOptions.expression).not.toContain('confident');
    expect(avatarOptions.expression).not.toContain('sad');
    expect(avatarOptions.accessory).toContain('paddle');
  });

  it('falls back safely when a removed expression remains in saved data', () => {
    expect(normalizeAvatarConfig({ ...defaultAvatarConfig, expression: 'sad' }).expression).toBe('happy');
    expect(normalizeAvatarConfig({ ...defaultAvatarConfig, expression: 'confident' }).expression).toBe('happy');
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
    if (config.facialHair === 'big-beard' || config.facialHair === 'wizard-beard') {
      expect(['bow', 'bandana', 'medal']).not.toContain(config.accessory);
    }
    vi.restoreAllMocks();
  });

  it('renders the original Pongo artwork untouched for the default fur', () => {
    const renderer = readFileSync(join(process.cwd(), 'components/BeaverAvatar.tsx'), 'utf8');
    expect(renderer).toContain('href="/pongo.webp"');
    expect(renderer).toContain("avatar.fur === 'brown' || avatar.fur === 'rainbow' ? undefined");
    expect(defaultAvatarConfig).toMatchObject({
      fur: 'brown', expression: 'happy', hat: 'none', glasses: 'none', facialHair: 'none', accessory: 'none',
    });
  });

  it('renders layers in a predictable order and keeps rainbow features readable', () => {
    const renderer = readFileSync(join(process.cwd(), 'components/BeaverAvatar.tsx'), 'utf8');
    const layers = ['fur', 'expression', 'facial-hair', 'glasses', 'hat', 'accessories'];
    const positions = layers.map((layer) => renderer.indexOf(`data-avatar-layer="${layer}"`));
    expect(positions.every((position) => position >= 0)).toBe(true);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
    expect(renderer).toContain("avatar.fur === 'rainbow'");
    expect(renderer).toContain('mixBlendMode');
  });
});
