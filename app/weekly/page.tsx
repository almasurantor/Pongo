import { redirect } from 'next/navigation';

export default function WeeklyPage() {
  redirect('/leaderboard?tab=weekly');
}
