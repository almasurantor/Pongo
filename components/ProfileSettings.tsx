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

function SettingSwitch({ checked, label, description, onChange, disabled = false }: {
  checked: boolean;
  label: string;
  description: string;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex min-h-14 items-center justify-between gap-4 rounded-2xl bg-accent-gray-50 px-4 py-3 dark:bg-[#0B1120]">
      <div className="min-w-0">
        <p className="font-black">{label}</p>
        <p className="text-xs leading-relaxed text-accent-gray-500">{description}</p>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`relative h-8 w-14 shrink-0 rounded-full transition disabled:cursor-not-allowed disabled:opacity-40 ${checked ? 'bg-[#2563EB]' : 'bg-accent-gray-300 dark:bg-[#475569]'}`}
      >
        <span className={`absolute left-1 top-1 h-6 w-6 rounded-full bg-white shadow-sm transition-transform ${checked ? 'translate-x-6' : 'translate-x-0'}`} />
      </button>
    </div>
  );
}

export default function ProfileSettings({ profile, onSaved }: {
  profile: Profile;
  onSaved: (profile: Profile) => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [savedName, setSavedName] = useState(profile.display_name);
  const [name, setName] = useState(profile.display_name);
  const [nameState, setNameState] = useState<NameState>('idle');
  const [soundEnabled, setSoundEnabled] = useState(profile.queue_turn_sound_enabled ?? true);
  const [pushEnabled, setPushEnabled] = useState(profile.queue_turn_push_enabled ?? false);
  const [pushSupported, setPushSupported] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setPushSupported('Notification' in window && 'serviceWorker' in navigator);
  }, []);

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

  const changePush = async (next: boolean) => {
    if (!next) {
      setPushEnabled(false);
      return;
    }
    if (!pushSupported) {
      toast.error('Queue reminders are not supported by this browser.');
      return;
    }
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') {
      toast.error('Allow notifications to enable queue turn reminders.');
      return;
    }
    setPushEnabled(true);
  };

  const save = async () => {
    const normalized = name.trim();
    if (!validName(normalized) || nameState === 'taken' || nameState === 'checking') return;
    setSaving(true);
    const { data, error } = await supabase.rpc('update_my_profile_settings_v4', {
      p_display_name: normalized,
      p_queue_turn_sound_enabled: soundEnabled,
      p_queue_turn_push_enabled: pushEnabled,
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
    toast.success('Settings saved');
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

      <SettingSwitch
        checked={soundEnabled}
        label="Queue turn sound"
        description="Play a short alert when your 60-second turn begins."
        onChange={setSoundEnabled}
      />
      <SettingSwitch
        checked={pushEnabled}
        label="Queue push reminder"
        description={pushSupported ? 'Show a device reminder while Pongo is running.' : 'Not supported by this browser.'}
        onChange={(next) => void changePush(next)}
        disabled={!pushSupported}
      />
      <button
        type="button"
        onClick={() => void save()}
        disabled={saving || nameState === 'checking' || nameState === 'taken' || nameState === 'invalid'}
        className="min-h-12 w-full rounded-xl bg-[#2563EB] px-4 font-black text-white transition active:scale-[.98] disabled:cursor-not-allowed disabled:opacity-45"
      >
        {saving ? 'Saving…' : 'Save settings'}
      </button>
    </div>
  );
}
