import { getRankDetails, RankTierName } from '@/lib/ranks';

const styles: Record<RankTierName, { shell: string; text: string; fill: string; accent: string }> = {
  Iron: { shell: 'border-slate-400 bg-slate-100', text: 'text-slate-700', fill: '#64748b', accent: '#cbd5e1' },
  Bronze: { shell: 'border-amber-600/40 bg-amber-50', text: 'text-amber-800', fill: '#b45309', accent: '#fbbf24' },
  Silver: { shell: 'border-slate-300 bg-slate-50', text: 'text-slate-700', fill: '#94a3b8', accent: '#e2e8f0' },
  Gold: { shell: 'border-yellow-400/60 bg-yellow-50', text: 'text-yellow-800', fill: '#eab308', accent: '#fef08a' },
  Platinum: { shell: 'border-cyan-400/50 bg-cyan-50', text: 'text-cyan-800', fill: '#0891b2', accent: '#a5f3fc' },
  Diamond: { shell: 'border-violet-400/50 bg-violet-50', text: 'text-violet-800', fill: '#7c3aed', accent: '#ddd6fe' },
  Legend: { shell: 'border-rose-400/50 bg-rose-50', text: 'text-rose-800', fill: '#e11d48', accent: '#fda4af' },
};

export function RankIcon({ tier, className = 'h-8 w-8' }: { tier: RankTierName; className?: string }) {
  const style = styles[tier];
  const tierIndex = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Legend'].indexOf(tier);
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden="true">
      <path d="M24 2 43 13v22L24 46 5 35V13Z" fill={style.fill} />
      <path d="m24 8 13 8v15l-13 8-13-8V16Z" fill={style.accent} />
      <path d="m24 12 9 12-9 12-9-12Z" fill={style.fill} />
      {tierIndex >= 3 && <path d="M8 12 2 20l7 3M40 12l6 8-7 3" fill="none" stroke={style.fill} strokeWidth="3" strokeLinecap="round" />}
      {tierIndex >= 5 && <path d="m17 7 7-6 7 6" fill="none" stroke={style.fill} strokeWidth="3" strokeLinejoin="round" />}
      <circle cx="24" cy="24" r={tierIndex >= 6 ? 4 : 2.5} fill="white" />
    </svg>
  );
}

interface RankBadgeProps {
  elo: number;
  totalGames?: number;
  compact?: boolean;
  className?: string;
}

export default function RankBadge({ elo, totalGames = 5, compact = false, className = '' }: RankBadgeProps) {
  const rank = getRankDetails(elo, totalGames);
  const style = styles[rank.tier];
  return (
    <span
      className={`inline-flex items-center rounded-full border font-black ${style.shell} ${style.text} ${compact ? 'gap-1.5 px-2 py-1 text-xs' : 'gap-2 px-3 py-1.5 text-sm'} ${className}`}
      aria-label={`${rank.isProvisional ? 'Provisional ' : ''}${rank.tier} rank`}
    >
      <RankIcon tier={rank.tier} className={compact ? 'h-5 w-5' : 'h-7 w-7'} />
      <span>{rank.isProvisional && <span className="mr-1 font-bold opacity-70">Provisional</span>}{rank.tier}</span>
    </span>
  );
}

export function RankProgress({ elo, totalGames, inverse = false }: { elo: number; totalGames: number; inverse?: boolean }) {
  const rank = getRankDetails(elo, totalGames);
  return (
    <div>
      <div className={`flex items-center justify-between text-xs font-bold ${inverse ? 'text-white/80' : 'text-accent-gray-600'}`}>
        <span>{rank.isTopTier ? 'Top competitive tier' : `${rank.pointsToNext} ELO to ${rank.nextTier}`}</span>
        <span>{rank.progressPercent}%</span>
      </div>
      <div className={`mt-2 h-2.5 overflow-hidden rounded-full ${inverse ? 'bg-white/20' : 'bg-accent-gray-200'}`}>
        <div
          className={`h-full rounded-full transition-all ${inverse ? 'bg-white' : 'gradient-purple'}`}
          style={{ width: `${rank.progressPercent}%` }}
        />
      </div>
      {rank.isProvisional && (
        <p className={`mt-2 text-xs font-bold ${inverse ? 'text-white/75' : 'text-accent-gray-500'}`}>
          {rank.placementGamesRemaining} placement {rank.placementGamesRemaining === 1 ? 'game' : 'games'} left
        </p>
      )}
    </div>
  );
}
