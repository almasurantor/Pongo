import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import AdminClient from './AdminClient';

export default async function AdminPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login');
  const { data: isAdmin } = await supabase.rpc('is_admin');
  if (!isAdmin) redirect('/dashboard');
  const [{ data: disputes }, { data: integrity }, { data: flags }] = await Promise.all([
    supabase.from('disputes').select(`*, match:matches(*, player_one:profiles!matches_player_one_id_fkey(*), player_two:profiles!matches_player_two_id_fkey(*))`).in('status', ['pending', 'admin_review']).order('created_at'),
    supabase.from('player_integrity').select('*, player:profiles(*)').order('confirmed_violations', { ascending: false }),
    supabase.from('integrity_flags').select('*, player:profiles(id,display_name), match:matches(id,player_one:profiles!matches_player_one_id_fkey(id,display_name),player_two:profiles!matches_player_two_id_fkey(id,display_name))').is('reviewed_at', null).order('created_at', { ascending: false }).limit(50),
  ]);
  return <AdminClient disputes={disputes || []} integrity={integrity || []} flags={flags || []} />;
}
