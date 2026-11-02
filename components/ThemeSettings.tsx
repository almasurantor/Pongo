'use client';

import { ThemePreference, useTheme } from './ThemeProvider';

const choices: { value: ThemePreference; label: string }[] = [
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'auto', label: 'Auto' },
];

export default function ThemeSettings() {
  const { preference, setPreference } = useTheme();

  return (
    <section className="rounded-3xl border border-accent-gray-200 bg-white p-5 shadow-sm">
      <h2 className="text-lg font-black">Appearance</h2>
      <div className="mt-3 grid grid-cols-3 gap-2" role="group" aria-label="Color theme">
        {choices.map((choice) => (
          <button
            key={choice.value}
            type="button"
            aria-pressed={preference === choice.value}
            onClick={() => setPreference(choice.value)}
            className={`min-h-11 rounded-xl text-sm font-bold transition ${
              preference === choice.value
                ? 'bg-primary-purple text-white shadow-sm'
                : 'bg-accent-gray-100 text-accent-gray-700 hover:bg-primary-purple/10'
            }`}
          >
            {choice.label}
          </button>
        ))}
      </div>
    </section>
  );
}

