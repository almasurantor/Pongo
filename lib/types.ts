export interface Profile {
  id: string;
  display_name: string;
  queue_turn_sound_enabled?: boolean;
  queue_turn_push_enabled?: boolean;
  current_elo: number;
  total_wins: number;
  total_losses: number;
  weekly_wins: number;
  weekly_losses: number;
  highest_elo: number;
  current_streak: number;
  longest_streak: number;
  created_at: string;
  updated_at: string;
}

export interface Challenge {
  id: string;
  challenger_id: string;
  opponent_id: string;
  status: 'pending' | 'accepted' | 'declined' | 'expired' | 'completed';
  created_at: string;
  expires_at: string;
  challenger?: Profile;
  opponent?: Profile;
}

export interface Match {
  id: string;
  challenge_id: string | null;
  player_one_id: string;
  player_two_id: string;
  player_one_score: number | null;
  player_two_score: number | null;
  status: MatchStatus;
  source: 'challenge' | 'spontaneous' | 'legacy';
  ranked: boolean;
  ranked_day: string | null;
  winner_id: string | null;
  verification_mode: 'normal' | 'dual';
  request_id: string | null;
  finalized_at: string | null;
  season_id: string | null;
  revision: number;
  reported_by: string | null;
  reported_at: string | null;
  confirmed_by: string | null;
  disputed_by: string | null;
  disputed_at: string | null;
  dispute_reason: string | null;
  expires_at: string | null;
  player_one_elo_before: number | null;
  player_two_elo_before: number | null;
  player_one_elo_change: number | null;
  player_two_elo_change: number | null;
  rating_calculation: RatingCalculation | null;
  confirmed_at: string | null;
  created_at: string;
  player_one?: Profile;
  player_two?: Profile;
}

export type MatchStatus =
  | 'ready' | 'result_reported' | 'confirmed' | 'expired' | 'canceled' | 'voided';

export interface MatchCancellationRequest {
  id: string;
  match_id: string;
  requested_by: string;
  responded_by: string | null;
  status: 'pending' | 'approved' | 'declined' | 'expired';
  created_at: string;
  responded_at: string | null;
}

export interface MatchSubmission {
  id: string;
  match_id: string;
  submitted_by: string;
  winner_id: string;
  player_one_score: number;
  player_two_score: number;
  created_at: string;
}

export interface RankedUsage {
  ranked_day: string;
  daily_used: number;
  daily_limit: number;
  daily_remaining: number;
  active_used: number;
  active_limit: number;
  active_remaining: number;
}

export interface OpponentRankedUsage {
  opponent_id: string;
  games_used: number;
  games_limit: number;
  games_remaining: number;
}

export type LeaderboardScope = 'weekly' | 'monthly' | 'all_time';

export interface LeaderboardEntry {
  placement: number;
  player_id: string;
  display_name: string;
  current_elo: number;
  current_rank: string;
  is_provisional: boolean;
  net_elo_change: number;
  total_games: number;
  wins: number;
  losses: number;
  win_rate: number;
  unique_opponents: number;
  period_start: string | null;
  period_end: string | null;
}

export interface LeaderboardArchiveEntry {
  scope: 'weekly' | 'monthly';
  period_start: string;
  period_end: string;
  winner_id: string;
  winner_name: string;
  winner_net_elo_change: number;
  winner_current_elo: number;
  winner_rank: string;
  winner_is_provisional: boolean;
  total_players: number;
}

export interface RatingCalculation {
  formula_version: 'weighted_elo_v1' | 'asymmetric_elo_v2';
  k_factor?: number;
  win_k_factor?: number;
  loss_k_factor?: number;
  winner_expected: number;
  loser_expected?: number;
  winner_gain_raw?: number;
  loser_loss_raw?: number;
  winner_gain?: number;
  loser_loss_unclamped?: number;
  loser_loss?: number;
  floor_applied?: boolean;
  score_margin_cap?: number;
  base_delta_raw?: number;
  base_delta?: number;
  score_margin?: number;
  margin_multiplier?: number;
  margin_bonus?: number;
  final_delta?: number;
  winner_id: string;
  loser_id: string;
  winner_rating_before: number;
  loser_rating_before: number;
}

export type VerificationLevel = 'normal' | 'monitored' | 'dual_verification' | 'ranked_restricted';

export interface RatingEvent {
  id: string;
  match_id: string | null;
  player_id: string;
  event_kind: 'match_result' | 'legacy_match' | 'opening_balance' | 'migration_adjustment' | 'reversal' | 'admin_adjustment';
  rating_before: number;
  rating_change: number;
  rating_after: number;
  revision: number;
  is_active: boolean;
  calculation?: RatingCalculation | null;
  rank_before?: string | null;
  rank_after?: string | null;
  created_at: string;
}

export interface Dispute {
  id: string;
  match_id: string;
  opened_by: string;
  reason: 'incorrect_score' | 'incorrect_winner' | 'match_never_happened' | 'other' | 'wrong_score' | 'wrong_winner' | 'dual_conflict';
  requested_resolution: 'correction' | 'void';
  original_winner_id: string;
  original_player_one_score: number;
  original_player_two_score: number;
  proposed_winner_id: string | null;
  proposed_player_one_score: number | null;
  proposed_player_two_score: number | null;
  status: 'pending' | 'admin_review' | 'resolved' | 'voided' | 'declined' | 'expired';
  responded_by: string | null;
  response: 'approved' | 'declined' | null;
  responded_at: string | null;
  expires_at: string | null;
  escalated_at: string | null;
  resolution?: 'original' | 'proposed' | 'custom' | 'no_violation' | 'voided' | null;
  created_at: string;
  match?: Match;
}

export interface MatchHistory {
  id: string;
  player_one_id: string;
  player_two_id: string;
  player_one_score: number;
  player_two_score: number;
  player_one_elo_change: number | null;
  player_two_elo_change: number | null;
  confirmed_at: string;
  created_at: string;
  winner_id: string | null;
  player_one?: Profile;
  player_two?: Profile;
}
