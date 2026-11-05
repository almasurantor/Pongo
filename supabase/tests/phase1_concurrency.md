# Phase 1 concurrency checks

Run these against a disposable database in two SQL sessions after the lifecycle
test has created equivalent fixtures. Keep each first transaction open before
starting the second.

1. **Concurrent acceptance cap:** lock the same participant profile in session
   A and accept one challenge in each session. After A commits, B must re-count
   the participant's active matches and reject any fourth match.
2. **Duplicate opponent acceptance:** accept opposite-direction challenges for
   the same unordered pair concurrently. Only one `ready` match may commit; the
   `one_ready_ranked_match_per_pair` index rejects the other.
3. **Conflicting reports:** submit different winners for the same `ready` match
   concurrently. Both calls return successfully, but the second reports
   `already_finalized=true`; only the first score and two rating events persist.
4. **Report versus cancellation approval:** hold the match row in the reporting
   transaction, approve cancellation in the other session, then reverse the
   order on a fresh match. The first transaction to lock the row determines the
   terminal state, and the loser cannot change ratings or status.
5. **Report versus expiration:** repeat the previous check with
   `expire_mobile_ranking_items_v2()`. At or after `expires_at`, expiration wins;
   before the deadline, a locked valid report may finalize normally.
6. **Daily reservation cap:** prepare a player with nine current-day
   reservations, then accept two challenges concurrently in separate sessions.
   Profile-row locking must let exactly one acceptance commit as reservation 10;
   the other must re-count and fail with the daily player limit.
7. **Shared opponent cap:** prepare an unordered pair with two confirmed Ranked
   games today, then accept a regular challenge in one session while accepting a
   queue Ranked request for the reversed pair in another. Stable profile-row
   locking must allow exactly one third reservation; the other must re-count and
   fail with the three-games-per-opponent limit.
8. **Weighted rating snapshot:** finalize two different matches involving the
   same player concurrently. Stable profile locking must make the second match
   calculate from the first match's updated rating, while each match and its two
   rating events retain their own immutable calculation JSON.
9. **Correction approval versus new report:** approve a historical correction
   in session A while session B submits a fresh result. The shared advisory lock
   must serialize both rating writes; the fresh match either participates in the
   replay or finalizes afterward from the replayed ratings, never from a partial
   state.
10. **Concurrent correction approvals:** approve disputes on two different
   matches in separate sessions. The shared replay lock must let one complete
   before the other obtains match/profile locks, with no deadlock and exactly
   one active rating-event pair per confirmed match revision.
11. **Independent dual reports:** mark one participant `dual_verification`, then
    submit each participant's report in separate sessions. Matching reports must
    retain two private submissions and finalize one rating-event pair. Conflicting
    reports must retain both submissions, expire the match and any pending
    cancellation request, emit one integrity flag, and apply no rating or record
    changes regardless of which session acquires the match lock first.
