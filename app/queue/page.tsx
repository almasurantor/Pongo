import { redirect } from 'next/navigation';
import QueueClient from './QueueClient';
import { getVerifiedUserId } from '@/lib/supabase/verified-user';

export const dynamic = 'force-dynamic';

export default async function QueuePage() {
  const userId = await getVerifiedUserId();
  if (!userId) redirect('/login');
  return <QueueClient currentUserId={userId} />;
}
