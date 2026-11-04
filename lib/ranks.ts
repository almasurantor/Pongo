export const STARTING_ELO = 50;

export type RankTierName =
  | 'Iron'
  | 'Bronze'
  | 'Silver'
  | 'Gold'
  | 'Platinum'
  | 'Diamond'
  | 'Legend';

export interface RankTier {
  name: RankTierName;
  minElo: number | null;
}

export interface RankDetails {
  tier: RankTierName;
  minElo: number | null;
  nextTier: RankTierName | null;
  nextTierElo: number | null;
  pointsToNext: number;
  progressPercent: number;
  isTopTier: boolean;
  gamesPlayed: number;
}

// Keep this in sync with the latest competitive_rank_tiers migration.
export const RANK_TIERS: readonly RankTier[] = [
  { name: 'Iron', minElo: null },
  { name: 'Bronze', minElo: 100 },
  { name: 'Silver', minElo: 200 },
  { name: 'Gold', minElo: 325 },
  { name: 'Platinum', minElo: 475 },
  { name: 'Diamond', minElo: 650 },
  { name: 'Legend', minElo: 850 },
] as const;

export function rankTierForElo(elo: number): RankTier {
  if (!Number.isFinite(elo)) throw new Error('ELO must be a finite number');
  for (let index = RANK_TIERS.length - 1; index >= 0; index -= 1) {
    const tier = RANK_TIERS[index];
    if (tier.minElo == null || elo >= tier.minElo) return tier;
  }
  return RANK_TIERS[0];
}

export function getRankDetails(elo: number, totalGames = 0): RankDetails {
  const tier = rankTierForElo(elo);
  const tierIndex = RANK_TIERS.findIndex((candidate) => candidate.name === tier.name);
  const nextTier = RANK_TIERS[tierIndex + 1] ?? null;
  const gamesPlayed = Math.max(0, Math.trunc(totalGames));

  if (!nextTier || nextTier.minElo == null) {
    return {
      tier: tier.name,
      minElo: tier.minElo,
      nextTier: null,
      nextTierElo: null,
      pointsToNext: 0,
      progressPercent: 100,
      isTopTier: true,
      gamesPlayed,
    };
  }

  // Ratings cannot be negative, so Iron progress spans the complete 0-99 tier.
  const progressFloor = tier.minElo ?? 0;
  const progressPercent = Math.round(
    Math.min(1, Math.max(0, (elo - progressFloor) / (nextTier.minElo - progressFloor))) * 100,
  );

  return {
    tier: tier.name,
    minElo: tier.minElo,
    nextTier: nextTier.name,
    nextTierElo: nextTier.minElo,
    pointsToNext: Math.max(nextTier.minElo - elo, 0),
    progressPercent,
    isTopTier: false,
    gamesPlayed,
  };
}

export function rankTransition(before: number, after: number) {
  const beforeTier = rankTierForElo(before).name;
  const afterTier = rankTierForElo(after).name;
  return {
    beforeTier,
    afterTier,
    changed: beforeTier !== afterTier,
    direction: beforeTier === afterTier ? null : after > before ? 'promotion' as const : 'demotion' as const,
  };
}
