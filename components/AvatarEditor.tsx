'use client';

import { useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import BeaverAvatar from '@/components/BeaverAvatar';
import { createClient } from '@/lib/supabase/client';
import { AvatarConfig, avatarLabels, avatarOptions, defaultAvatarConfig, normalizeAvatarConfig, randomAvatarConfig } from '@/lib/avatar';

const categories = ['fur', 'hat', 'glasses', 'facialHair', 'expression', 'accessory'] as const;

export default function AvatarEditor({ initialConfig, onSaved, onClose }: { initialConfig?: unknown; onSaved: (config: AvatarConfig) => void; onClose: () => void }) {
  const supabase = useMemo(() => createClient(), []);
  const [config, setConfig] = useState(() => normalizeAvatarConfig(initialConfig));
  const [activeCategory, setActiveCategory] = useState<typeof categories[number]>('fur');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(); };
    window.addEventListener('keydown', closeOnEscape);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', closeOnEscape);
    };
  }, [onClose]);

  const save = async () => {
    setSaving(true);
    const { data, error } = await supabase.rpc('update_my_avatar_v1', { p_avatar_config: config });
    setSaving(false);
    if (error) { toast.error(error.message); return; }
    const saved = normalizeAvatarConfig(data);
    setConfig(saved);
    onSaved(saved);
    toast.success('Pongo avatar saved');
    onClose();
  };

  const options = avatarOptions[activeCategory];
  return (
    <div className="fixed inset-0 z-[100] flex bg-[#07152F]/80 p-0 backdrop-blur-md sm:p-5" role="dialog" aria-modal="true" aria-labelledby="avatar-editor-title">
    <section className="mx-auto flex h-[100dvh] w-full max-w-6xl flex-col overflow-hidden bg-white shadow-2xl dark:bg-[#0B1120] sm:h-[calc(100dvh-2.5rem)] sm:rounded-3xl sm:border-2 sm:border-[#BFD3F8]">
      <div className="flex shrink-0 items-start justify-between gap-4 bg-gradient-to-br from-[#0F5FD7] to-[#083B91] px-5 py-4 text-white sm:px-7 sm:py-5">
        <div><p className="text-xs font-black uppercase tracking-[.16em] text-[#FFB068]">Experimental</p>
        <h2 id="avatar-editor-title" className="mt-1 text-2xl font-black">Customize Pongo</h2>
        <p className="mt-1 text-sm text-white/75">Mix a look that feels like you. Changes stay private until you save.</p></div>
        <button type="button" onClick={onClose} aria-label="Close avatar editor" className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-white/15 text-2xl font-black transition hover:bg-white/25">×</button>
      </div>
      <div className="grid min-h-0 flex-1 gap-5 overflow-y-auto p-4 sm:p-6 md:grid-cols-[minmax(17rem,.85fr)_minmax(0,1.15fr)] md:overflow-hidden">
        <div className="flex flex-col items-center justify-center rounded-3xl bg-[#EAF2FF] p-4 dark:bg-[#14213D]">
          <BeaverAvatar config={config} className="aspect-square w-full max-w-[23rem] drop-shadow-xl" label="Live preview of your Pongo avatar" />
          <span className="mt-2 rounded-full bg-white px-3 py-1 text-xs font-black text-[#174EA6] shadow-sm">LIVE PREVIEW</span>
        </div>
        <div className="min-w-0 md:overflow-y-auto md:pr-1">
          <div className="flex gap-2 overflow-x-auto pb-2" role="tablist" aria-label="Avatar categories">
            {categories.map((category) => <button key={category} type="button" role="tab" aria-selected={category === activeCategory} onClick={() => setActiveCategory(category)} className={`min-h-11 shrink-0 rounded-xl px-3 text-sm font-black transition ${category === activeCategory ? 'bg-[#2563EB] text-white' : 'bg-[#EFF4FC] text-[#29466F]'}`}>{avatarLabels[category]}</button>)}
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3" role="tabpanel" aria-label={avatarLabels[activeCategory]}>
            {options.map((option) => {
              const selected = config[activeCategory] === option;
              return <button key={option} type="button" aria-pressed={selected} onClick={() => setConfig((current) => ({ ...current, [activeCategory]: option }))} className={`min-h-14 rounded-xl border-2 px-2 py-2 text-sm font-bold transition ${selected ? 'border-[#FF7A1A] bg-[#FFF3E8] text-[#9A3E00]' : 'border-[#DCE5F3] bg-white text-[#29466F] hover:border-[#2563EB]'}`}><span className="block truncate">{avatarLabels[option]}</span></button>;
            })}
          </div>
          <div className="mt-5 grid gap-2 sm:grid-cols-2">
            <button type="button" onClick={() => setConfig(randomAvatarConfig())} className="min-h-12 rounded-xl border-2 border-[#2563EB]/20 bg-[#EFF6FF] font-black text-[#1D4ED8]">Surprise me</button>
            <button type="button" onClick={() => setConfig(defaultAvatarConfig)} className="min-h-12 rounded-xl border-2 border-[#DCE5F3] font-black text-[#526987]">Reset to default</button>
          </div>
          <button type="button" onClick={() => void save()} disabled={saving} className="mt-2 min-h-14 w-full rounded-xl bg-[#FF7A1A] px-4 font-black text-white shadow-lg shadow-orange-500/20 transition active:scale-[.98] disabled:opacity-50">{saving ? 'Saving Pongo…' : 'Save Avatar'}</button>
          <button type="button" onClick={onClose} disabled={saving} className="mt-2 min-h-12 w-full rounded-xl font-black text-[#526987] dark:text-[#B7C3E0]">Cancel</button>
        </div>
      </div>
    </section>
    </div>
  );
}
