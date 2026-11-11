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
  rainbow: { hue: 0, saturation: 1, brightness: 1 },
};

const overlayColors: Record<AvatarConfig['fur'], { fur: string; dark: string; muzzle: string }> = {
  brown: { fur: '#F0A04B', dark: '#5F341D', muzzle: '#FFE4B8' },
  tan: { fur: '#E6B06F', dark: '#735035', muzzle: '#FFF0D2' },
  cream: { fur: '#EBD3AF', dark: '#806B54', muzzle: '#FFF5E4' },
  gray: { fur: '#9DA4AD', dark: '#4A5059', muzzle: '#E7E9EC' },
  black: { fur: '#42464D', dark: '#171A20', muzzle: '#AEB2B8' },
  blue: { fur: '#4384E8', dark: '#17458F', muzzle: '#C4DCFF' },
  pink: { fur: '#E985AD', dark: '#9B3D68', muzzle: '#FFD9E7' },
  rainbow: { fur: '#7C8EF5', dark: '#3B2B6B', muzzle: '#FFF1D7' },
};

export default function BeaverAvatar({ config, className = '', label = 'Pongo the beaver avatar' }: {
  config?: AvatarConfig | null | unknown;
  className?: string;
  label?: string;
}) {
  const avatar = normalizeAvatarConfig(config);
  const treatment = furTreatments[avatar.fur];
  const colors = overlayColors[avatar.fur];
  const id = useId().replace(/:/g, '');
  const filterId = `pongo-fur-${id}`;
  const rainbowId = `pongo-rainbow-${id}`;
  const silhouetteId = `pongo-silhouette-${id}`;
  const filter = avatar.fur === 'brown' || avatar.fur === 'rainbow' ? undefined : `url(#${filterId})`;
  const outline = '#17120F';

  return (
    <svg viewBox="-12 -20 264 275" role="img" aria-label={label} className={className} overflow="hidden">
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
        <linearGradient id={rainbowId} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#FF4D6D" />
          <stop offset=".2" stopColor="#FF9F1C" />
          <stop offset=".4" stopColor="#FFE66D" />
          <stop offset=".58" stopColor="#35D07F" />
          <stop offset=".76" stopColor="#3B82F6" />
          <stop offset="1" stopColor="#A855F7" />
        </linearGradient>
        <mask id={silhouetteId} maskUnits="userSpaceOnUse" x="2" y="2" width="236" height="236">
          <image href="/pongo.webp" x="2" y="2" width="236" height="236" preserveAspectRatio="xMidYMid meet" />
        </mask>
      </defs>

      {/* The headphone band sits behind the mascot; its ear pieces remain in the accessory layer. */}
      {avatar.accessory === 'headphones' && <path d="M35 102a85 85 0 0 1 170 0" fill="none" stroke="#183C78" strokeWidth="14" strokeLinecap="round" />}

      <g data-avatar-layer="fur">
        <image href="/pongo.webp" x="2" y="2" width="236" height="236" preserveAspectRatio="xMidYMid meet" filter={filter} />
        {avatar.fur === 'rainbow' && (
          <rect x="2" y="2" width="236" height="236" fill={`url(#${rainbowId})`} mask={`url(#${silhouetteId})`} opacity=".88" style={{ mixBlendMode: 'color' }} />
        )}
      </g>

      <g data-avatar-layer="expression">
        {avatar.expression === 'mischievous' && <><path d="M65 81q17-18 34 0" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /><path d="M141 81q17-18 34 0" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /><circle cx="61" cy="145" r="8" fill="#FF7996" opacity=".65" /><circle cx="179" cy="145" r="8" fill="#FF7996" opacity=".65" /></>}
        {avatar.expression === 'angry' && <><path d="m64 77 35 13" fill="none" stroke={outline} strokeWidth="8" strokeLinecap="round" /><path d="m141 90 35-13" fill="none" stroke={outline} strokeWidth="8" strokeLinecap="round" /><path d="M99 190q21-16 42 0" fill="none" stroke={outline} strokeWidth="6" strokeLinecap="round" /></>}
        {avatar.expression === 'sleepy' && <><ellipse cx="82" cy="105" rx="22" ry="23" fill={colors.fur} /><ellipse cx="158" cy="105" rx="22" ry="23" fill={colors.fur} /><path d="M65 105q17 13 34 0" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /><path d="M141 105q17 13 34 0" fill="none" stroke={outline} strokeWidth="7" strokeLinecap="round" /></>}
      </g>

      <g data-avatar-layer="facial-hair">
        {avatar.facialHair === 'mustache' && <path d="M117 146c-18-2-23 15-48 8 11 19 36 24 51 4 15 20 40 15 51-4-25 7-30-10-48-8z" fill={colors.dark} stroke={outline} strokeWidth="2" />}
        {avatar.facialHair === 'curled-mustache' && <><path d="M119 147q-21-12-34 4-12 16-27 2 7 27 32 15 15-7 30-11z" fill={colors.dark} stroke={outline} strokeWidth="2" /><path d="M121 147q21-12 34 4 12 16 27 2-7 27-32 15-15-7-30-11z" fill={colors.dark} stroke={outline} strokeWidth="2" /></>}
        {avatar.facialHair === 'handlebar-mustache' && <path d="M119 145q-20-12-35 5-15 17-36 3 7 35 42 20 15-7 30-16 15 9 30 16 35 15 42-20-21 14-36-3-15-17-35-5z" fill={colors.dark} stroke={outline} strokeWidth="3" />}
        {avatar.facialHair === 'goatee' && <path d="m104 196 16 34 16-34q-16 10-32 0z" fill={colors.dark} stroke={outline} strokeWidth="2" />}
        {avatar.facialHair === 'short-beard' && <path d="M72 165q48 67 96 0-5 63-48 64t-48-64z" fill={colors.dark} stroke={outline} strokeWidth="3" opacity=".96" />}
        {avatar.facialHair === 'big-beard' && <path d="M61 157q12 73 59 85 47-12 59-85-15 15-28 12-15 33-31 21-16 12-31-21-13 3-28-12z" fill={colors.dark} stroke={outline} strokeWidth="4" strokeLinejoin="round" />}
        {avatar.facialHair === 'wizard-beard' && <path d="M67 157q8 50 28 56l9 29 16-18 16 18 9-29q20-6 28-56-18 19-38 10-15 31-30 0-20 9-38-10z" fill="#F4F0E8" stroke={outline} strokeWidth="4" strokeLinejoin="round" />}
      </g>

      <g data-avatar-layer="glasses">
        {avatar.glasses === 'sunglasses' && <><path d="M53 87h63v39H72q-15 0-19-39zm71 0h63q-4 39-19 39h-44z" fill="#172033" stroke={outline} strokeWidth="5" /><path d="M115 99h10" stroke={outline} strokeWidth="8" /></>}
        {(avatar.glasses === 'round' || avatar.glasses === 'nerd') && <><circle cx="82" cy="105" r={avatar.glasses === 'round' ? 27 : 24} fill="none" stroke={avatar.glasses === 'nerd' ? outline : '#2563EB'} strokeWidth={avatar.glasses === 'nerd' ? 7 : 5} /><circle cx="158" cy="105" r={avatar.glasses === 'round' ? 27 : 24} fill="none" stroke={avatar.glasses === 'nerd' ? outline : '#2563EB'} strokeWidth={avatar.glasses === 'nerd' ? 7 : 5} /><path d="M109 103h22" stroke={avatar.glasses === 'nerd' ? outline : '#2563EB'} strokeWidth="7" /></>}
        {avatar.glasses === 'heart' && <><path d="M82 126C69 116 55 106 57 93c2-15 20-17 25-5 5-12 23-10 25 5 2 13-12 23-25 33z" fill="#F43F5E" fillOpacity=".28" stroke="#E11D48" strokeWidth="5" /><path d="M158 126c-13-10-27-20-25-33 2-15 20-17 25-5 5-12 23-10 25 5 2 13-12 23-25 33z" fill="#F43F5E" fillOpacity=".28" stroke="#E11D48" strokeWidth="5" /><path d="M107 100h26" stroke="#E11D48" strokeWidth="6" /></>}
        {avatar.glasses === 'star' && <><path d="m82 76 8 18 20 2-15 13 5 20-18-10-18 10 5-20-15-13 20-2z" fill="#FDE047" fillOpacity=".3" stroke="#EAB308" strokeWidth="5" strokeLinejoin="round" /><path d="m158 76 8 18 20 2-15 13 5 20-18-10-18 10 5-20-15-13 20-2z" fill="#FDE047" fillOpacity=".3" stroke="#EAB308" strokeWidth="5" strokeLinejoin="round" /><path d="M109 101h22" stroke="#EAB308" strokeWidth="6" /></>}
        {avatar.glasses === 'reading' && <><ellipse cx="82" cy="116" rx="21" ry="16" fill="none" stroke="#6D4C41" strokeWidth="5" /><ellipse cx="158" cy="116" rx="21" ry="16" fill="none" stroke="#6D4C41" strokeWidth="5" /><path d="M103 114h34M61 111l-13-5m131 5 13-5" fill="none" stroke="#6D4C41" strokeWidth="5" strokeLinecap="round" /></>}
        {avatar.glasses === 'goggles' && <><path d="M47 96h18m110 0h18" stroke="#0F172A" strokeWidth="8" /><rect x="58" y="82" width="53" height="46" rx="18" fill="#67E8F9" fillOpacity=".42" stroke="#0F172A" strokeWidth="7" /><rect x="129" y="82" width="53" height="46" rx="18" fill="#67E8F9" fillOpacity=".42" stroke="#0F172A" strokeWidth="7" /><path d="M111 101h18" stroke="#0F172A" strokeWidth="8" /></>}
      </g>

      <g data-avatar-layer="hat">
        {avatar.hat === 'baseball-cap' && <><path d="M47 57q21-53 73-49 49 1 67 50z" fill="#2563EB" stroke={outline} strokeWidth="6" /><path d="M119 57q56-4 89 15-64 13-121-5z" fill="#174EA6" stroke={outline} strokeWidth="4" /></>}
        {avatar.hat === 'beanie' && <><path d="M50 62Q62 3 120 3t70 59z" fill="#FF7A1A" stroke={outline} strokeWidth="6" /><rect x="45" y="49" width="150" height="28" rx="14" fill="#E85C00" stroke={outline} strokeWidth="5" /><circle cx="120" cy="1" r="14" fill="#2563EB" stroke={outline} strokeWidth="4" /></>}
        {avatar.hat === 'crown' && <path d="m53 59 10-56 37 30 20-38 23 38 36-30 9 56z" fill="#FFC928" stroke={outline} strokeWidth="6" strokeLinejoin="round" />}
        {avatar.hat === 'bucket-hat' && <><path d="m65 16 110 0 16 53H49z" fill="#FFB35C" stroke={outline} strokeWidth="6" /><ellipse cx="120" cy="65" rx="88" ry="20" fill="#FF7A1A" stroke={outline} strokeWidth="6" /></>}
        {avatar.hat === 'party-hat' && <><path d="m120-8 54 76H66z" fill="#2563EB" stroke={outline} strokeWidth="6" /><circle cx="120" cy="-7" r="12" fill="#FF7A1A" stroke={outline} strokeWidth="3" /><circle cx="108" cy="29" r="6" fill="#FFC928" /><circle cx="141" cy="51" r="6" fill="#FF7A1A" /></>}
        {avatar.hat === 'wizard-hat' && <><path d="M82 58 128-13l34 74z" fill="#6D28D9" stroke={outline} strokeWidth="6" strokeLinejoin="round" /><path d="m121 9 5 10 11 2-8 8 2 11-10-5-10 5 2-11-8-8 11-2z" fill="#FDE047" /><ellipse cx="121" cy="61" rx="76" ry="16" fill="#7C3AED" stroke={outline} strokeWidth="6" /></>}
        {avatar.hat === 'dickhead-hat' && <><rect x="55" y="51" width="130" height="22" rx="11" fill="#22C55E" stroke={outline} strokeWidth="5" /><path d="M120 50V29" stroke={outline} strokeWidth="5" /><path d="m112 31 16-9-16-9 16-9" fill="none" stroke="#F43F5E" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" /><rect x="74" y="-16" width="92" height="34" rx="12" fill="#FDE047" stroke={outline} strokeWidth="5" /><text x="120" y="7" textAnchor="middle" fontSize="14" fontWeight="900" fill={outline}>DICKHEAD</text></>}
      </g>

      <g data-avatar-layer="accessories">
        {avatar.accessory === 'gold-chain' && <><path d="M67 205q53 46 106 0" fill="none" stroke="#FACC15" strokeWidth="9" strokeLinecap="round" strokeDasharray="5 7" /><circle cx="120" cy="229" r="13" fill="#FACC15" stroke="#A16207" strokeWidth="4" /><path d="m120 220 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z" fill="#FFF7B2" /></>}
        {avatar.accessory === 'bow' && <><path d="m120 205-32-18-16 28 42 15z" fill="#FF7A1A" stroke={outline} strokeWidth="4" /><path d="m120 205 32-18 16 28-42 15z" fill="#FF7A1A" stroke={outline} strokeWidth="4" /><circle cx="120" cy="210" r="12" fill="#E85C00" stroke={outline} strokeWidth="3" /></>}
        {avatar.accessory === 'headphones' && <><rect x="23" y="93" width="33" height="65" rx="16" fill="#FF7A1A" stroke={outline} strokeWidth="5" /><rect x="184" y="93" width="33" height="65" rx="16" fill="#FF7A1A" stroke={outline} strokeWidth="5" /></>}
        {avatar.accessory === 'earrings' && <><circle cx="34" cy="124" r="10" fill="none" stroke="#FACC15" strokeWidth="5" /><circle cx="206" cy="124" r="10" fill="none" stroke="#FACC15" strokeWidth="5" /></>}
        {avatar.accessory === 'bandana' && <><path d="M47 194q73 38 146 0l-10 35q-63 19-126 0z" fill="#FF7A1A" stroke={outline} strokeWidth="4" /><path d="m180 211 32 18-25 9z" fill="#E85C00" stroke={outline} strokeWidth="3" /></>}
        {avatar.accessory === 'medal' && <><path d="m99 198 16 28 5-20 5 20 16-28" fill="#2563EB" stroke={outline} strokeWidth="4" strokeLinejoin="round" /><circle cx="120" cy="228" r="17" fill="#FACC15" stroke="#A16207" strokeWidth="4" /><path d="m120 217 3 7 8 1-6 5 2 8-7-4-7 4 2-8-6-5 8-1z" fill="#FFF7B2" /></>}
        {avatar.accessory === 'paddle' && <><g transform="rotate(18 205 186)"><ellipse cx="205" cy="166" rx="24" ry="29" fill="#EF4444" stroke={outline} strokeWidth="5" /><rect x="198" y="187" width="14" height="47" rx="7" fill="#A16207" stroke={outline} strokeWidth="4" /></g><circle cx="181" cy="218" r="9" fill="#F97316" stroke={outline} strokeWidth="3" /></>}
      </g>
    </svg>
  );
}
