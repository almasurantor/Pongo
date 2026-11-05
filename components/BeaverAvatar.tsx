import { useId } from 'react';
import { AvatarConfig, normalizeAvatarConfig } from '@/lib/avatar';

const furTreatments: Record<AvatarConfig['fur'], { hue: number; saturation: number; brightness: number }> = {
  brown: { hue: 0, saturation: 1, brightness: 1 },
  tan: { hue: -8, saturation: .78, brightness: 1.08 },
  cream: { hue: -12, saturation: .28, brightness: 1.2 },
  gray: { hue: 0, saturation: 0, brightness: .9 },
  black: { hue: 0, saturation: .18, brightness: .48 },
  blue: { hue: 175, saturation: 1.2, brightness: .92 },
  pink: { hue: 292, saturation: 1.05, brightness: 1.05 },
};

const overlayColors: Record<AvatarConfig['fur'], { fur: string; dark: string; muzzle: string }> = {
  brown: { fur: '#F0A04B', dark: '#5F341D', muzzle: '#FFE4B8' },
  tan: { fur: '#E6B06F', dark: '#735035', muzzle: '#FFF0D2' },
  cream: { fur: '#EBD3AF', dark: '#806B54', muzzle: '#FFF5E4' },
  gray: { fur: '#9DA4AD', dark: '#4A5059', muzzle: '#E7E9EC' },
  black: { fur: '#42464D', dark: '#171A20', muzzle: '#AEB2B8' },
  blue: { fur: '#4384E8', dark: '#17458F', muzzle: '#C4DCFF' },
  pink: { fur: '#E985AD', dark: '#9B3D68', muzzle: '#FFD9E7' },
};

export default function BeaverAvatar({ config, className = '', label = 'Pongo the beaver avatar' }: {
  config?: AvatarConfig | null | unknown;
  className?: string;
  label?: string;
}) {
  const avatar = normalizeAvatarConfig(config);
  const treatment = furTreatments[avatar.fur];
  const colors = overlayColors[avatar.fur];
  const filterId = `pongo-fur-${useId().replace(/:/g, '')}`;
  const filter = avatar.fur === 'brown' ? undefined : `url(#${filterId})`;
  const outline = '#17120F';

  return (
    <svg viewBox="-12 -20 264 275" role="img" aria-label={label} className={className} overflow="visible">
      <defs>
        <filter id={filterId} x="-10%" y="-10%" width="120%" height="120%" colorInterpolationFilters="sRGB">
          <feColorMatrix type="hueRotate" values={String(treatment.hue)} />
          <feColorMatrix type="saturate" values={String(treatment.saturation)} />
          <feComponentTransfer>
            <feFuncR type="linear" slope={treatment.brightness} />
            <feFuncG type="linear" slope={treatment.brightness} />
            <feFuncB type="linear" slope={treatment.brightness} />
          </feComponentTransfer>
        </filter>
      </defs>

      {avatar.accessory === 'headphones' && <><path d="M35 102a85 85 0 0 1 170 0" fill="none" stroke="#183C78" strokeWidth="14" strokeLinecap="round" /><rect x="23" y="93" width="33" height="65" rx="16" fill="#FF7A1A" stroke={outline} strokeWidth="5" /><rect x="184" y="93" width="33" height="65" rx="16" fill="#FF7A1A" stroke={outline} strokeWidth="5" /></>}

      {/* The real transparent Pongo artwork is the character base. Default config renders it untouched. */}
      <image href="/pongo.webp" x="2" y="2" width="236" height="236" preserveAspectRatio="xMidYMid meet" filter={filter} />

      {avatar.expression === 'confident' && <><path d="m66 84 32-9" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /><path d="m142 75 32 9" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /></>}
      {avatar.expression === 'mischievous' && <><path d="m66 77 32 11" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /><path d="m142 88 32-11" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /></>}
      {avatar.expression === 'sleepy' && <><ellipse cx="82" cy="105" rx="22" ry="23" fill={colors.fur} /><ellipse cx="158" cy="105" rx="22" ry="23" fill={colors.fur} /><path d="M65 105q17 13 34 0" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /><path d="M141 105q17 13 34 0" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /></>}
      {avatar.expression === 'surprised' && <ellipse cx="120" cy="181" rx="14" ry="18" fill={outline} stroke={colors.muzzle} strokeWidth="5" />}

      {avatar.glasses !== 'none' && (avatar.glasses === 'sunglasses' ? <><path d="M53 87h63v39H72q-15 0-19-39zm71 0h63q-4 39-19 39h-44z" fill="#172033" stroke={outline} strokeWidth="5" /><path d="M115 99h10" stroke={outline} strokeWidth="8" /></> : <><circle cx="82" cy="105" r={avatar.glasses === 'round' ? 27 : 24} fill="none" stroke={avatar.glasses === 'nerd' ? outline : '#2563EB'} strokeWidth={avatar.glasses === 'nerd' ? 7 : 5} /><circle cx="158" cy="105" r={avatar.glasses === 'round' ? 27 : 24} fill="none" stroke={avatar.glasses === 'nerd' ? outline : '#2563EB'} strokeWidth={avatar.glasses === 'nerd' ? 7 : 5} /><path d="M109 103h22" stroke={avatar.glasses === 'nerd' ? outline : '#2563EB'} strokeWidth="7" /></>)}

      {avatar.facialHair === 'mustache' && <path d="M117 146c-18-2-23 15-48 8 11 19 36 24 51 4 15 20 40 15 51-4-25 7-30-10-48-8z" fill={colors.dark} stroke={outline} strokeWidth="2" />}
      {avatar.facialHair === 'short-beard' && <path d="M72 165q48 67 96 0-5 63-48 64t-48-64z" fill={colors.dark} stroke={outline} strokeWidth="3" opacity=".96" />}
      {avatar.facialHair === 'goatee' && <path d="m104 196 16 34 16-34q-16 10-32 0z" fill={colors.dark} stroke={outline} strokeWidth="2" />}

      {avatar.accessory === 'bandana' && <><path d="M47 194q73 38 146 0l-10 35q-63 19-126 0z" fill="#FF7A1A" stroke={outline} strokeWidth="4" /><path d="m180 211 32 18-25 9z" fill="#E85C00" stroke={outline} strokeWidth="3" /></>}
      {avatar.accessory === 'bow' && <><path d="m120 205-32-18-16 28 42 15z" fill="#FF7A1A" stroke={outline} strokeWidth="4" /><path d="m120 205 32-18 16 28-42 15z" fill="#FF7A1A" stroke={outline} strokeWidth="4" /><circle cx="120" cy="210" r="12" fill="#E85C00" stroke={outline} strokeWidth="3" /></>}

      {avatar.hat === 'baseball-cap' && <><path d="M47 57q21-53 73-49 49 1 67 50z" fill="#2563EB" stroke={outline} strokeWidth="6" /><path d="M119 57q56-4 89 15-64 13-121-5z" fill="#174EA6" stroke={outline} strokeWidth="4" /></>}
      {avatar.hat === 'beanie' && <><path d="M50 62Q62 3 120 3t70 59z" fill="#FF7A1A" stroke={outline} strokeWidth="6" /><rect x="45" y="49" width="150" height="28" rx="14" fill="#E85C00" stroke={outline} strokeWidth="5" /><circle cx="120" cy="1" r="14" fill="#2563EB" stroke={outline} strokeWidth="4" /></>}
      {avatar.hat === 'crown' && <path d="m53 59 10-56 37 30 20-38 23 38 36-30 9 56z" fill="#FFC928" stroke={outline} strokeWidth="6" strokeLinejoin="round" />}
      {avatar.hat === 'bucket-hat' && <><path d="m65 16 110 0 16 53H49z" fill="#FFB35C" stroke={outline} strokeWidth="6" /><ellipse cx="120" cy="65" rx="88" ry="20" fill="#FF7A1A" stroke={outline} strokeWidth="6" /></>}
      {avatar.hat === 'party-hat' && <><path d="m120-8 54 76H66z" fill="#2563EB" stroke={outline} strokeWidth="6" /><circle cx="120" cy="-7" r="12" fill="#FF7A1A" stroke={outline} strokeWidth="3" /><circle cx="108" cy="29" r="6" fill="#FFC928" /><circle cx="141" cy="51" r="6" fill="#FF7A1A" /></>}
    </svg>
  );
}
