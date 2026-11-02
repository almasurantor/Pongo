import { describe, expect, it } from 'vitest';
import { validateMatchScore } from './match-result';
import { orderedQueueLine, queuePlaceFor, QueueLineMember } from './queue';

const member = (userId: string, status: QueueLineMember['status'], position: number): QueueLineMember => ({
  user_id: userId,
  status,
  queue_position: position,
});

describe('live queue presentation rules', () => {
  it('keeps waiting players in FIFO order and puts the called player first', () => {
    const line = orderedQueueLine([
      member('third', 'waiting', 30),
      member('holder', 'king', 10),
      member('called', 'called', 20),
      member('second-waiting', 'waiting', 25),
      member('left', 'left', 5),
    ]);
    expect(line.map((entry) => entry.user_id)).toEqual(['called', 'second-waiting', 'third']);
  });

  it('reports a stable queue position and number of players ahead', () => {
    const members = [
      member('called', 'called', 2),
      member('next', 'waiting', 3),
      member('me', 'waiting', 4),
    ];
    expect(queuePlaceFor(members, 'me')).toEqual({ position: 3, playersAhead: 2 });
    expect(queuePlaceFor(members, 'missing')).toBeNull();
  });

  it('uses the shared table-tennis score rules', () => {
    expect(validateMatchScore(11, 9)).toBeNull();
    expect(validateMatchScore(12, 10)).toBeNull();
    expect(validateMatchScore(11, 10)).toMatch(/2 points/);
    expect(validateMatchScore(13, 10)).toMatch(/exactly 2/);
  });
});
