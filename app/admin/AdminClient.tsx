'use client';

import { useState } from 'react';
import toast from 'react-hot-toast';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import { useRouter } from 'next/navigation';

type PlayerSummary = { id: string; display_name: string };
type AdminDispute = {
  id: string;
  reason: string;
  status: string;
  requested_resolution: 'correction' | 'void';
  original_player_one_score: number;
  original_player_two_score: number;
  original_winner_id: string;
  proposed_player_one_score: number;
  proposed_player_two_score: number;
  proposed_winner_id: string;
  match: {
    player_one_id: string;
    player_two_id: string;
    player_one: PlayerSummary;
    player_two: PlayerSummary;
  };
};
type IntegrityLevel = 'normal' | 'monitored' | 'dual_verification' | 'ranked_restricted';
type IntegrityRow = {
  player_id: string;
  verification_level: IntegrityLevel;
  confirmed_violations: number;
  player: PlayerSummary | null;
};
type IntegrityFlag = {
  id: string;
  flag_type: string;
  details: Record<string, unknown>;
  created_at: string;
  player: PlayerSummary | null;
  match: { player_one: PlayerSummary; player_two: PlayerSummary } | null;
};
type ResolutionPayload = {
  winner_id?: string;
  winner_score?: number;
  loser_score?: number;
  violation_user_id?: string | null;
  notes?: string;
};

export default function AdminClient({ disputes, integrity, flags }: { disputes: AdminDispute[]; integrity: IntegrityRow[]; flags: IntegrityFlag[] }) {
  const router = useRouter();
  useDatabaseRefresh('admin-review', ['disputes', 'integrity_flags', 'player_integrity']);
  const [selected, setSelected] = useState<AdminDispute | null>(null);
  const [loading, setLoading] = useState(false);
  const [customWinner, setCustomWinner] = useState('');
  const [customWinnerScore, setCustomWinnerScore] = useState(11);
  const [customLoserScore, setCustomLoserScore] = useState(0);
  const [notes, setNotes] = useState('');
  const [violationUser, setViolationUser] = useState('');
  const [violationResolution, setViolationResolution] = useState<'original' | 'proposed' | 'custom' | 'voided'>('original');
  const openDispute = (dispute: AdminDispute) => {
    setSelected(dispute);
    setCustomWinner(dispute.original_winner_id);
    setCustomWinnerScore(Math.max(dispute.original_player_one_score, dispute.original_player_two_score));
    setCustomLoserScore(Math.min(dispute.original_player_one_score, dispute.original_player_two_score));
    setNotes('');
    setViolationUser(dispute.match.player_one_id);
    setViolationResolution('original');
  };
  const resolve = async (resolution: string, payload: ResolutionPayload = {}) => {
    if (!selected) return;
    if ((resolution === 'voided' || payload.violation_user_id) && !window.confirm(payload.violation_user_id ? 'Apply this resolution and assign a confirmed reporting violation?' : 'Void this match and replay affected ratings?')) return;
    setLoading(true);
    try { const response=await fetch(`/api/admin/disputes/${selected.id}/resolve`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({resolution,...payload,notes:payload.notes ?? notes})});const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not resolve dispute');toast.success('Dispute resolved');setSelected(null);router.refresh(); }
    catch(error){toast.error(error instanceof Error?error.message:'Could not resolve dispute');}finally{setLoading(false);}
  };
  const setLevel = async (playerId:string,level:IntegrityLevel) => {
    if(level==='ranked_restricted'&&!window.confirm('Restrict this player from all ranked play?'))return;
    try{const response=await fetch(`/api/admin/players/${playerId}/integrity`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({level})});const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not update player');toast.success('Integrity level updated');router.refresh();}catch(error){toast.error(error instanceof Error?error.message:'Could not update player');}
  };
  const reviewFlag = async (flagId: string) => {
    try { const response=await fetch(`/api/admin/integrity-flags/${flagId}/review`,{method:'POST'});const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not review flag');toast.success('Integrity flag reviewed');router.refresh(); }
    catch(error){toast.error(error instanceof Error?error.message:'Could not review flag');}
  };
  const resolveWithViolation = () => {
    const payload: ResolutionPayload = { violation_user_id: violationUser };
    if (violationResolution === 'custom') {
      payload.winner_id = customWinner;
      payload.winner_score = customWinnerScore;
      payload.loser_score = customLoserScore;
    }
    void resolve(violationResolution, payload);
  };
  const resultText=(d:AdminDispute,proposed=false)=>{const m=d.match;const one=proposed?d.proposed_player_one_score:d.original_player_one_score;const two=proposed?d.proposed_player_two_score:d.original_player_two_score;return `${m.player_one.display_name} ${one}–${two} ${m.player_two.display_name}`;};
  return <main className="min-h-screen bg-accent-gray-50 px-4 py-7"><div className="mx-auto max-w-5xl"><h1 className="text-4xl font-black">Integrity</h1><div className="mt-8 grid gap-8 lg:grid-cols-[1.4fr_1fr]"><section><h2 className="text-xl font-black">Disputes</h2><div className="mt-3 space-y-3">{disputes.map(d=><button key={d.id} onClick={()=>openDispute(d)} className="w-full rounded-2xl border-2 border-accent-gray-200 bg-white p-5 text-left"><div className="flex justify-between"><span className="font-black">{d.match.player_one.display_name} vs {d.match.player_two.display_name}</span><span className="rounded-full bg-amber-100 px-2 py-1 text-xs font-bold text-amber-800">{d.status.replace('_',' ')}</span></div><p className="mt-2 text-sm text-accent-gray-500">Original: {resultText(d)} · Proposed: {resultText(d,true)}</p></button>)}{!disputes.length&&<div className="rounded-2xl bg-white p-8 text-center text-accent-gray-500">No unresolved disputes.</div>}</div></section><section><h2 className="text-xl font-black">Player integrity</h2><div className="mt-3 space-y-3">{integrity.map(row=><div key={row.player_id} className="rounded-2xl bg-white p-4"><p className="font-black">{row.player?.display_name}</p><p className="text-sm text-accent-gray-500">{row.confirmed_violations} confirmed violations</p><select aria-label={`Integrity level for ${row.player?.display_name}`} value={row.verification_level} onChange={e=>setLevel(row.player_id,e.target.value as IntegrityLevel)} className="mt-3 h-11 w-full rounded-xl border-2 border-accent-gray-200 px-3 font-bold"><option value="normal">Normal</option><option value="monitored">Monitored</option><option value="dual_verification">Dual verification</option><option value="ranked_restricted">Ranked restricted</option></select></div>)}</div></section></div>
      <section className="mt-8"><h2 className="text-xl font-black">Signals</h2><div className="mt-3 grid gap-3 sm:grid-cols-2">{flags.map(flag=><div key={flag.id} className="rounded-2xl border-2 border-accent-gray-200 bg-white p-4"><div className="flex items-start justify-between gap-3"><div><p className="font-black">{flag.flag_type.replaceAll('_',' ')}</p><p className="mt-1 text-sm text-accent-gray-500">{flag.player?.display_name || (flag.match ? `${flag.match.player_one.display_name} vs ${flag.match.player_two.display_name}` : 'System signal')}</p></div><button onClick={()=>reviewFlag(flag.id)} className="rounded-xl border-2 border-accent-gray-200 px-3 py-2 text-sm font-black">Reviewed</button></div><p className="mt-3 break-words text-xs text-accent-gray-400">{JSON.stringify(flag.details)}</p></div>)}{!flags.length&&<div className="rounded-2xl bg-white p-8 text-center text-accent-gray-500">No unreviewed integrity signals.</div>}</div></section>
      {selected&&<div role="dialog" aria-modal="true" className="fixed inset-0 z-[70] flex items-end bg-black/50 p-4 sm:items-center sm:justify-center"><div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-3xl bg-white p-6"><h2 className="text-2xl font-black">Review dispute</h2><div className="mt-4 rounded-2xl bg-accent-gray-50 p-4"><p className="text-sm font-bold text-accent-gray-500">Original report</p><p className="text-lg font-black">{resultText(selected)}</p><p className="mt-4 text-sm font-bold text-accent-gray-500">Requested resolution</p><p className="text-lg font-black">{selected.requested_resolution==='void'?'Void this match':resultText(selected,true)}</p><p className="mt-3 text-sm text-accent-gray-500">Reason: {selected.reason.replaceAll('_',' ')}</p></div><div className="mt-5 space-y-2"><button disabled={loading} onClick={()=>resolve('original')} className="min-h-12 w-full rounded-xl bg-primary-purple font-bold text-white">Keep original result</button><button disabled={loading} onClick={()=>resolve('proposed')} className="min-h-12 w-full rounded-xl bg-green-600 font-bold text-white">Approve requested {selected.requested_resolution}</button><button disabled={loading} onClick={()=>resolve('no_violation')} className="min-h-12 w-full rounded-xl border-2 border-accent-gray-300 font-bold">Resolve original — no violation</button><div className="rounded-2xl border-2 border-accent-gray-200 p-3"><p className="font-black">Enter another valid result</p><select aria-label="Resolved winner" value={customWinner} onChange={e=>setCustomWinner(e.target.value)} className="mt-2 h-11 w-full rounded-xl border px-3"><option value={selected.match.player_one_id}>{selected.match.player_one.display_name}</option><option value={selected.match.player_two_id}>{selected.match.player_two.display_name}</option></select><div className="mt-2 grid grid-cols-2 gap-2"><input aria-label="Winner score" type="number" min="0" max="99" value={customWinnerScore} onChange={e=>setCustomWinnerScore(Number(e.target.value))} className="h-11 rounded-xl border px-3"/><input aria-label="Loser score" type="number" min="0" max="99" value={customLoserScore} onChange={e=>setCustomLoserScore(Number(e.target.value))} className="h-11 rounded-xl border px-3"/></div><button disabled={loading} onClick={()=>resolve('custom',{winner_id:customWinner,winner_score:customWinnerScore,loser_score:customLoserScore})} className="mt-2 min-h-12 w-full rounded-xl bg-accent-gray-900 font-bold text-white">Approve custom result</button></div><textarea aria-label="Private admin notes" placeholder="Private admin notes (optional)" value={notes} onChange={e=>setNotes(e.target.value)} className="min-h-24 w-full rounded-xl border-2 border-accent-gray-200 p-3"/><div className="rounded-2xl border-2 border-red-200 bg-red-50 p-3"><p className="font-black text-red-800">Record a confirmed violation</p><div className="mt-2 grid gap-2 sm:grid-cols-2"><select aria-label="Player responsible for violation" value={violationUser} onChange={e=>setViolationUser(e.target.value)} className="h-11 rounded-xl border px-3"><option value={selected.match.player_one_id}>{selected.match.player_one.display_name}</option><option value={selected.match.player_two_id}>{selected.match.player_two.display_name}</option></select><select aria-label="Resolution applied with violation" value={violationResolution} onChange={e=>setViolationResolution(e.target.value as 'original'|'proposed'|'custom'|'voided')} className="h-11 rounded-xl border px-3"><option value="original">Keep original</option><option value="proposed">Approve request</option><option value="custom">Use custom result</option><option value="voided">Void match</option></select></div><button disabled={loading||!violationUser} onClick={resolveWithViolation} className="mt-2 min-h-12 w-full rounded-xl border-2 border-red-300 text-sm font-bold text-red-700">Resolve and record violation</button></div><button disabled={loading} onClick={()=>resolve('voided')} className="min-h-12 w-full font-bold text-red-600">Void duplicate/nonexistent match</button><button onClick={()=>setSelected(null)} className="min-h-12 w-full font-bold text-accent-gray-500">Close</button></div></div></div>}
    </div></main>;
}
