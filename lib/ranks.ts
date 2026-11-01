export const PLACEMENT_GAME_COUNT = 5;

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
  placementGamesRemaining: number;
  isProvisional: boolean;
}

// Keep this in sync with competitive_rank_tiers in the Phase 4 migration.
export const RANK_TIERS: readonly RankTier[] = [
  { name: 'Iron', minElo: null },
  { name: 'Bronze', minElo: 850 },
  { name: 'Silver', minElo: 950 },
  { name: 'Gold', minElo: 1050 },
  { name: 'Platinum', minElo: 1150 },
  { name: 'Diamond', minElo: 1250 },
  { name: 'Legend', minElo: 1400 },
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
  const placementGamesRemaining = Math.max(PLACEMENT_GAME_COUNT - gamesPlayed, 0);

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
      placementGamesRemaining,
      isProvisional: placementGamesRemaining > 0,
    };
  }

  // Iron has no lower bound, so use one normal 100-point tier band for its bar.
  const progressFloor = tier.minElo ?? nextTier.minElo - 100;
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
    placementGamesRemaining,
    isProvisional: placementGamesRemaining > 0,
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
