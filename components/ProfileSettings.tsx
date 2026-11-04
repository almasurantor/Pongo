'use client';

import { useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { createClient } from '@/lib/supabase/client';
import { Profile } from '@/lib/types';

type NameState = 'idle' | 'checking' | 'available' | 'taken' | 'invalid' | 'saved';

const validName = (name: string) => {
  const normalized = name.trim();
  return normalized.length >= 3
    && normalized.length <= 20
    && /^[A-Za-z0-9][A-Za-z0-9 _.]*[A-Za-z0-9]$/.test(normalized);
};

export default function ProfileSettings({ profile, onSaved }: {
  profile: Profile;
  onSaved: (profile: Profile) => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [savedName, setSavedName] = useState(profile.display_name);
  const [name, setName] = useState(profile.display_name);
  const [nameState, setNameState] = useState<NameState>('idle');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const normalized = name.trim();
    if (!validName(name)) {
      setNameState('invalid');
      return;
    }
    if (normalized === savedName) {
      setNameState((current) => current === 'saved' ? current : 'available');
      return;
    }
    setNameState('checking');
    const timer = window.setTimeout(async () => {
      const { data, error } = await supabase.rpc('check_display_name_available_v4', { p_name: normalized });
      if (error) {
        setNameState('invalid');
        return;
      }
      const result = data as { valid?: boolean; available?: boolean } | null;
      setNameState(!result?.valid ? 'invalid' : result.available ? 'available' : 'taken');
    }, 300);
    return () => window.clearTimeout(timer);
  }, [name, savedName, supabase]);

  const save = async () => {
    const normalized = name.trim();
    if (!validName(normalized) || nameState === 'taken' || nameState === 'checking') return;
    setSaving(true);
    const { data, error } = await supabase.rpc('update_my_profile_settings_v4', {
      p_display_name: normalized,
      // Preserve the legacy columns while these controls are retired from UI.
      p_queue_turn_sound_enabled: profile.queue_turn_sound_enabled ?? true,
      p_queue_turn_push_enabled: profile.queue_turn_push_enabled ?? false,
    });
    setSaving(false);
    if (error) {
      setNameState(error.message.toLowerCase().includes('taken') ? 'taken' : 'invalid');
      toast.error(error.message);
      return;
    }
    const updated = (Array.isArray(data) ? data[0] : data) as Profile;
    setSavedName(updated.display_name);
    setName(updated.display_name);
    setNameState('saved');
    onSaved(updated);
    toast.success('Profile saved');
  };

  const status = nameState === 'checking' ? 'Checking…'
    : nameState === 'available' ? 'Available'
      : nameState === 'taken' ? 'Name already taken'
        : nameState === 'invalid' ? 'Invalid name'
          : nameState === 'saved' ? 'Saved' : '';
  const statusColor = nameState === 'available' || nameState === 'saved'
    ? 'text-green-600' : nameState === 'checking' || nameState === 'idle'
      ? 'text-accent-gray-500' : 'text-red-600';

  return (
    <div className="space-y-3">
      <div>
        <label htmlFor="display-name" className="text-sm font-black">Display name</label>
        <input
          id="display-name"
          value={name}
          maxLength={20}
          autoComplete="nickname"
          spellCheck={false}
          onChange={(event) => { setName(event.target.value); setNameState('idle'); }}
          className="mt-2 min-h-12 w-full rounded-xl border-2 border-accent-gray-200 bg-white px-4 text-base outline-none transition focus:border-[#2563EB] dark:bg-[#0B1120]"
          aria-describedby="display-name-help display-name-status"
        />
        <div className="mt-2 grid min-h-5 gap-1 text-xs sm:grid-cols-[minmax(0,1fr)_auto] sm:items-start sm:gap-3">
          <p id="display-name-help" className="text-accent-gray-500">3–20 letters, numbers, spaces, underscores, or periods.</p>
          <p id="display-name-status" aria-live="polite" className={`min-h-4 font-black sm:text-right ${statusColor}`}>{status}</p>
        </div>
      </div>

      <button
        type="button"
        onClick={() => void save()}
        disabled={saving || nameState === 'checking' || nameState === 'taken' || nameState === 'invalid'}
        className="min-h-12 w-full rounded-xl bg-[#2563EB] px-4 font-black text-white transition active:scale-[.98] disabled:cursor-not-allowed disabled:opacity-45"
      >
        {saving ? 'Saving…' : 'Save profile'}
      </button>
    </div>
  );
}
