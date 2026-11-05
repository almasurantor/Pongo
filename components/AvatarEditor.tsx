'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import BeaverAvatar from '@/components/BeaverAvatar';
import InAppConfirmDialog from '@/components/InAppConfirmDialog';
import { createClient } from '@/lib/supabase/client';
import { AvatarConfig, avatarLabels, avatarOptions, defaultAvatarConfig, normalizeAvatarConfig, randomAvatarConfig } from '@/lib/avatar';

const categories = ['fur', 'hat', 'glasses', 'facialHair', 'expression', 'accessory'] as const;

export default function AvatarEditor({ initialConfig, onSaved, onClose }: {
  initialConfig?: unknown;
  onSaved: (config: AvatarConfig) => void;
  onClose: () => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const initial = useMemo(() => normalizeAvatarConfig(initialConfig), [initialConfig]);
  const [config, setConfig] = useState(initial);
  const [activeCategory, setActiveCategory] = useState<typeof categories[number]>('fur');
  const [saving, setSaving] = useState(false);
  const [confirmDiscard, setConfirmDiscard] = useState(false);
  const dirty = JSON.stringify(config) !== JSON.stringify(initial);

  const requestClose = useCallback(() => {
    if (dirty) { setConfirmDiscard(true); return; }
    onClose();
  }, [dirty, onClose]);

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      if (confirmDiscard) setConfirmDiscard(false);
      else requestClose();
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', closeOnEscape);
    };
  }, [confirmDiscard, requestClose]);

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
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-[#07152F]/80 backdrop-blur-md"
      style={{
        paddingTop: 'max(.5rem, env(safe-area-inset-top))',
        paddingRight: 'max(.5rem, env(safe-area-inset-right))',
        paddingBottom: 'max(.5rem, env(safe-area-inset-bottom))',
        paddingLeft: 'max(.5rem, env(safe-area-inset-left))',
      }}
      role="dialog"
      aria-modal="true"
      aria-labelledby="avatar-editor-title"
    >
      <section className="mx-auto flex h-[calc(100dvh-1rem)] max-h-[46rem] w-full max-w-4xl flex-col overflow-hidden rounded-[2rem] border border-[#BFD3F8] bg-white shadow-2xl dark:border-[#334155] dark:bg-[#0B1120] sm:h-[min(44rem,calc(100dvh-2rem))]">
        <header className="flex shrink-0 items-center justify-between gap-3 bg-gradient-to-r from-[#0F5FD7] to-[#2563EB] px-4 py-3 text-white sm:px-5">
          <h2 id="avatar-editor-title" className="text-xl font-black sm:text-2xl">Customize Pongo</h2>
          <button type="button" onClick={requestClose} aria-label="Close avatar editor" className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-white/15 text-2xl font-black transition hover:bg-white/25 active:scale-95">×</button>
        </header>

        <div className="grid min-h-0 flex-1 grid-rows-[auto_minmax(0,1fr)] gap-3 overflow-hidden p-3 md:grid-cols-[minmax(14rem,.8fr)_minmax(0,1.2fr)] md:grid-rows-1 md:gap-4 md:p-5">
          <div className="flex h-[clamp(8.5rem,23dvh,13rem)] items-center justify-center overflow-hidden rounded-[1.65rem] bg-[#EAF2FF] px-3 dark:bg-[#14213D] md:h-auto md:min-h-0">
            <BeaverAvatar config={config} className="h-[95%] max-h-[22rem] w-auto max-w-full drop-shadow-xl" label="Live preview of your Pongo avatar" />
          </div>

          <div className="flex min-h-0 min-w-0 flex-col overflow-hidden">
            <div className="flex shrink-0 gap-2 overflow-x-auto pb-2 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden" role="tablist" aria-label="Avatar categories">
              {categories.map((category) => <button key={category} type="button" role="tab" aria-selected={category === activeCategory} onClick={() => setActiveCategory(category)} className={`min-h-10 shrink-0 rounded-full px-3.5 text-sm font-black transition ${category === activeCategory ? 'bg-[#2563EB] text-white shadow-sm' : 'bg-[#E8EEF8] text-[#29466F] hover:bg-[#DCE7F8] dark:bg-[#1E293B] dark:text-[#E2E8F0] dark:hover:bg-[#334155]'}`}>{avatarLabels[category]}</button>)}
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain pb-2 pr-1 [scrollbar-width:thin]" role="tabpanel" aria-label={avatarLabels[activeCategory]}>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {options.map((option) => {
                  const selected = config[activeCategory] === option;
                  return <button key={option} type="button" aria-pressed={selected} onClick={() => setConfig((current) => ({ ...current, [activeCategory]: option }))} className={`min-h-12 rounded-2xl px-2.5 py-2 text-sm font-bold transition ${selected ? 'bg-[#FFF0E2] text-[#9A3E00] ring-2 ring-inset ring-[#FF7A1A] dark:bg-[#3A2418] dark:text-[#FDBA74]' : 'bg-[#F1F5F9] text-[#334155] hover:bg-[#E2E8F0] dark:bg-[#172033] dark:text-[#E2E8F0] dark:hover:bg-[#243047]'}`}><span className="block truncate">{avatarLabels[option]}</span></button>;
                })}
              </div>
            </div>

            <footer className="shrink-0 border-t border-accent-gray-200 bg-white pt-2 dark:border-[#334155] dark:bg-[#0B1120]">
              <div className="grid grid-cols-2 gap-2">
                <button type="button" onClick={() => setConfig(randomAvatarConfig())} className="min-h-11 rounded-2xl bg-[#EFF6FF] px-2 text-sm font-black text-[#1D4ED8] dark:bg-[#17243C] dark:text-[#93C5FD]">Surprise me</button>
                <button type="button" onClick={() => setConfig(defaultAvatarConfig)} className="min-h-11 rounded-2xl bg-accent-gray-100 px-2 text-sm font-black text-[#526987] dark:bg-[#1E293B] dark:text-[#CBD5E1]">Reset default</button>
              </div>
              <button type="button" onClick={() => void save()} disabled={saving} className="mt-2 min-h-12 w-full rounded-2xl bg-[#FF7A1A] px-4 font-black text-white shadow-lg shadow-orange-500/20 transition active:scale-[.98] disabled:opacity-50">{saving ? 'Saving Pongo…' : 'Save Avatar'}</button>
            </footer>
          </div>
        </div>
      </section>
      {confirmDiscard && (
        <InAppConfirmDialog
          title="Discard avatar changes?"
          message="Your unsaved Pongo customizations will be lost."
          cancelLabel="Keep editing"
          confirmLabel="Discard"
          onCancel={() => setConfirmDiscard(false)}
          onConfirm={onClose}
        />
      )}
    </div>
  );
}
