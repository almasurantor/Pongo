'use client';

import { useId } from 'react';

export default function InAppPromptDialog({
  title,
  message,
  label,
  value,
  placeholder,
  confirmLabel,
  onChange,
  onConfirm,
  onCancel,
}: {
  title: string;
  message: string;
  label: string;
  value: string;
  placeholder?: string;
  confirmLabel: string;
  onChange: (value: string) => void;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const titleId = useId();
  const messageId = useId();

  return (
    <div className="fixed inset-0 z-[160] flex items-center justify-center bg-[#07152F]/75 p-4 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={messageId}>
      <form onSubmit={(event) => { event.preventDefault(); onConfirm(); }} className="w-full max-w-md rounded-[1.75rem] border border-[#BFD3F8] bg-white p-5 text-slate-900 shadow-2xl dark:border-slate-700 dark:bg-[#111827] dark:text-white sm:p-6">
        <h2 id={titleId} className="text-xl font-black">{title}</h2>
        <p id={messageId} className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">{message}</p>
        <label className="mt-4 block text-sm font-black">
          {label}
          <textarea autoFocus value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} className="mt-2 min-h-24 w-full resize-y rounded-2xl border-2 border-slate-200 bg-white p-3 font-normal text-slate-900 outline-none transition focus:border-[#2563EB] focus:ring-2 focus:ring-blue-500/15 dark:border-slate-600 dark:bg-[#0B1120] dark:text-white" />
        </label>
        <div className="mt-5 grid grid-cols-2 gap-2">
          <button type="button" onClick={onCancel} className="min-h-12 rounded-2xl bg-slate-100 px-3 font-black text-slate-700 transition hover:bg-slate-200 dark:bg-slate-800 dark:text-slate-100">Cancel</button>
          <button type="submit" className="min-h-12 rounded-2xl bg-[#2563EB] px-3 font-black text-white transition hover:bg-[#1D4ED8] active:scale-[.98]">{confirmLabel}</button>
        </div>
      </form>
    </div>
  );
}
