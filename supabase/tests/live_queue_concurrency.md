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

## Competing final scores

1. Start one game and copy its `game_id` into both participant sessions.
2. Begin both transactions. Submit different valid scores with
   `beaver_queue_report_v1(game_id, king_score, challenger_score)` and commit.
3. One request must complete; the other blocks on the singleton row and then fails with
   `This game is no longer active`. Verify one game row, one winner, one holder, and no
   ranked match or rating event.

## Confirmation at the deadline

1. Call a challenger and set `call_expires_at` a few seconds ahead.
2. At the boundary, call `beaver_queue_confirm_v1()` as the challenger while a service
   session calls `beaver_queue_advance_expired_v1()`.
3. Whichever transaction locks the singleton first decides the outcome using database
   time: either the game is `playing`, or the challenger is `no_show` and the next
   waiting player is called. It must never produce both outcomes.

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
