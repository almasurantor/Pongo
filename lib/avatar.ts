export const avatarOptions = {
  fur: ['brown', 'tan', 'cream', 'gray', 'black', 'blue', 'pink'],
  hat: ['none', 'baseball-cap', 'beanie', 'crown', 'bucket-hat', 'party-hat'],
  glasses: ['none', 'sunglasses', 'round', 'nerd'],
  facialHair: ['none', 'mustache', 'short-beard', 'goatee'],
  expression: ['happy', 'confident', 'sleepy', 'surprised', 'mischievous'],
  accessory: ['none', 'headphones', 'bow', 'bandana'],
} as const;

export type AvatarConfig = {
  version: 1;
  fur: typeof avatarOptions.fur[number];
  hat: typeof avatarOptions.hat[number];
  glasses: typeof avatarOptions.glasses[number];
  facialHair: typeof avatarOptions.facialHair[number];
  expression: typeof avatarOptions.expression[number];
  accessory: typeof avatarOptions.accessory[number];
};

export const defaultAvatarConfig: AvatarConfig = {
  version: 1,
  fur: 'brown',
  hat: 'none',
  glasses: 'none',
  facialHair: 'none',
  expression: 'happy',
  accessory: 'none',
};

export function normalizeAvatarConfig(value: unknown): AvatarConfig {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return defaultAvatarConfig;
  const candidate = value as Record<string, unknown>;
  const valid = <T extends readonly string[]>(options: T, key: keyof AvatarConfig, fallback: T[number]) =>
    options.includes(candidate[key] as T[number]) ? candidate[key] as T[number] : fallback;
  return {
    version: 1,
    fur: valid(avatarOptions.fur, 'fur', defaultAvatarConfig.fur),
    hat: valid(avatarOptions.hat, 'hat', defaultAvatarConfig.hat),
    glasses: valid(avatarOptions.glasses, 'glasses', defaultAvatarConfig.glasses),
    facialHair: valid(avatarOptions.facialHair, 'facialHair', defaultAvatarConfig.facialHair),
    expression: valid(avatarOptions.expression, 'expression', defaultAvatarConfig.expression),
    accessory: valid(avatarOptions.accessory, 'accessory', defaultAvatarConfig.accessory),
  };
}

export function randomAvatarConfig(): AvatarConfig {
  const pick = <T extends readonly string[]>(options: T): T[number] => options[Math.floor(Math.random() * options.length)];
  return {
    version: 1,
    fur: pick(avatarOptions.fur),
    hat: pick(avatarOptions.hat),
    glasses: pick(avatarOptions.glasses),
    facialHair: pick(avatarOptions.facialHair),
    expression: pick(avatarOptions.expression),
    accessory: pick(avatarOptions.accessory),
  };
}

export const avatarLabels: Record<string, string> = {
  fur: 'Fur', hat: 'Hats', glasses: 'Glasses', facialHair: 'Facial hair', expression: 'Expression', accessory: 'Accessories',
  brown: 'Original orange', tan: 'Golden tan', cream: 'Cream', gray: 'Silver gray', black: 'Midnight', blue: 'Pongo blue', pink: 'Bubblegum',
  none: 'None', 'baseball-cap': 'Baseball cap', beanie: 'Beanie', crown: 'Crown', 'bucket-hat': 'Bucket hat', 'party-hat': 'Party hat',
  sunglasses: 'Sunglasses', round: 'Round glasses', nerd: 'Nerd glasses', mustache: 'Mustache', 'short-beard': 'Short beard', goatee: 'Goatee',
  happy: 'Happy', confident: 'Confident', sleepy: 'Sleepy', surprised: 'Surprised', mischievous: 'Mischievous',
  headphones: 'Headphones', bow: 'Bow tie', bandana: 'Bandana',
};
