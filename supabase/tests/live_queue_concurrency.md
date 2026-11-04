# Live queue concurrency checks

Run these only against a disposable Supabase database after applying every migration and
running `live_queue.test.sql`. Use two authenticated SQL/API sessions and inspect state
from a third owner/service-role session. The queue singleton row is the serialization
point for every mutation.

## Simultaneous joins

1. Reset the queue to `idle` with no holder or members.
2. In session A and session B, begin transactions as two different authenticated users.
3. Call `beaver_queue_join_v1()` in both sessions, then commit both.
4. Verify exactly one member is `king`, the other is `called`, their queue positions are
   distinct, and the smaller committed sequence position was selected first. Repeating
   either join must not change membership or position.

## Competing outcomes

1. Start one game and copy its `game_id` into both participant sessions.
2. Begin both transactions. Submit conflicting outcomes with
   `beaver_queue_report_outcome_v2(game_id, 'won')` from both players and commit.
3. One request must complete; the other blocks on the singleton row and then receives the
   conflicting-finalization/admin-correction error. An identical retry by either player
   must return `idempotent: true`. Verify one completed game row, one winner, one holder,
   and no ranked match or rating event.

## Swap acceptance versus departure/advancement

1. Create a pending request from a waiting player behind to a waiting player ahead.
2. Race `beaver_queue_respond_swap_v1(request_id, 'accept')` in the target session
   against `beaver_queue_leave_v1()` in the requester session.
3. The singleton lock must produce exactly one valid result: either the positions swap
   before the requester leaves, or the departure cancels the request before acceptance.
   Verify there are no duplicate positions and no pending request involving a non-waiting
   player.
4. Repeat while the trusted worker advances an expired call. A player promoted to called
   or holder must have every pending swap canceled before an acceptance can change spots.

## Confirmation at the deadline

1. Assign a holder and challenger and set `call_expires_at` a few seconds ahead. The
   holder must already have `king_confirmed_at`; only the challenger is pending.
2. At the boundary, call `beaver_queue_confirm_v1()` as the challenger while a service
   session calls `beaver_queue_advance_expired_v1()`.
3. Whichever transaction locks the singleton first decides the outcome using database
   time: either the game is `playing`, or the challenger is `no_show` and the holder
   remains. It must never produce both outcomes or extend the deadline.

## Match result versus expiration

1. Start a game, copy its `game_id`, and set `game_expires_at` a few seconds ahead.
2. At the deadline, race a participant's `beaver_queue_report_outcome_v2()` call against
   two simultaneous `beaver_queue_advance_expired_v1()` calls from trusted sessions.
3. The singleton lock and database timestamp must produce exactly one terminal state:
   either a result committed before the deadline, or one `abandoned` audit row with no
   winner or loser. For expiration, both participants must be `left` and waiting players
   must advance once. Repeated workers must not affect the newly advanced match.

## Departure versus call/report

1. Race a called challenger’s `beaver_queue_leave_v1()` against their confirmation.
2. Race a holder departure between games against another player joining.
3. Verify all final states satisfy: at most one `king`, at most one `called`, a playing
   game has exactly its two participants, and waiting players remain ordered by
   `queue_position`.

Supabase Realtime may deliver duplicate or out-of-order change notifications; each client
must respond by refetching the authoritative table, member, and recent-game rows. The UI
also polls every four seconds and refetches on focus, covering reconnects and dropped
Realtime messages.
