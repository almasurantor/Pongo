export const avatarOptions = {
  fur: ['brown', 'tan', 'cream', 'gray', 'black', 'blue', 'pink', 'rainbow'],
  hat: ['none', 'baseball-cap', 'beanie', 'crown', 'bucket-hat', 'party-hat', 'wizard-hat', 'dickhead-hat'],
  glasses: ['none', 'round', 'nerd', 'sunglasses', 'heart', 'star', 'reading', 'goggles'],
  facialHair: ['none', 'mustache', 'curled-mustache', 'handlebar-mustache', 'goatee', 'short-beard', 'big-beard', 'wizard-beard'],
  expression: ['happy', 'mischievous', 'angry', 'sleepy'],
  accessory: ['none', 'gold-chain', 'bow', 'headphones', 'earrings', 'bandana', 'medal', 'paddle'],
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
  const facialHair = pick(avatarOptions.facialHair);
  const accessories = facialHair === 'big-beard' || facialHair === 'wizard-beard'
    ? avatarOptions.accessory.filter((option) => !['bow', 'bandana', 'medal'].includes(option))
    : avatarOptions.accessory;
  return {
    version: 1,
    fur: pick(avatarOptions.fur),
    hat: pick(avatarOptions.hat),
    glasses: pick(avatarOptions.glasses),
    facialHair,
    expression: pick(avatarOptions.expression),
    accessory: pick(accessories),
  };
}

export const avatarLabels: Record<string, string> = {
  fur: 'Fur', hat: 'Hats', glasses: 'Glasses', facialHair: 'Facial Hair', expression: 'Expressions', accessory: 'Accessories',
  brown: 'Original orange', tan: 'Golden tan', cream: 'Cream', gray: 'Silver gray', black: 'Midnight', blue: 'Pongo blue', pink: 'Bubblegum', rainbow: 'Rainbow',
  none: 'None', 'baseball-cap': 'Baseball cap', beanie: 'Beanie', crown: 'Crown', 'bucket-hat': 'Bucket hat', 'party-hat': 'Party hat', 'wizard-hat': 'Wizard hat', 'dickhead-hat': 'Dickhead hat',
  round: 'Round glasses', nerd: 'Nerd glasses', sunglasses: 'Sunglasses', heart: 'Heart glasses', star: 'Star glasses', reading: 'Tiny reading glasses', goggles: 'Sport goggles',
  mustache: 'Small mustache', 'curled-mustache': 'Curled mustache', 'handlebar-mustache': 'Handlebar mustache', goatee: 'Goatee', 'short-beard': 'Short beard', 'big-beard': 'Big beard', 'wizard-beard': 'Wizard beard',
  happy: 'Default happy', mischievous: 'Excited', angry: 'Angry', sleepy: 'Sleepy',
  'gold-chain': 'Gold chain', bow: 'Bow tie', headphones: 'Headphones', earrings: 'Earrings', bandana: 'Bandana', medal: 'Medal', paddle: 'Ping-pong paddle',
};
