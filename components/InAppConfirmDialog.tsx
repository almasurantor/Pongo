'use client';

import { useId } from 'react';

export default function InAppConfirmDialog({
  title,
  message,
  confirmLabel,
  cancelLabel = 'Cancel',
  onConfirm,
  onCancel,
}: {
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel?: string;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const titleId = useId();
  const messageId = useId();

  return (
    <div
      className="fixed inset-0 z-[160] flex items-center justify-center bg-[#07152F]/75 p-4 backdrop-blur-sm"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby={titleId}
      aria-describedby={messageId}
      onMouseDown={(event) => { if (event.target === event.currentTarget) onCancel(); }}
    >
      <section className="w-full max-w-sm rounded-[1.75rem] border border-[#BFD3F8] bg-white p-5 text-slate-900 shadow-2xl dark:border-slate-700 dark:bg-[#111827] dark:text-white sm:p-6">
        <div className="mx-auto grid h-12 w-12 place-items-center rounded-full bg-[#FFF0E2] text-2xl" aria-hidden="true">!</div>
        <h2 id={titleId} className="mt-4 text-center text-xl font-black">{title}</h2>
        <p id={messageId} className="mt-2 text-center text-sm leading-6 text-slate-600 dark:text-slate-300">{message}</p>
        <div className="mt-5 grid grid-cols-2 gap-2">
          <button type="button" onClick={onCancel} className="min-h-12 rounded-2xl bg-slate-100 px-3 font-black text-slate-700 transition hover:bg-slate-200 dark:bg-slate-800 dark:text-slate-100 dark:hover:bg-slate-700">{cancelLabel}</button>
          <button type="button" onClick={onConfirm} autoFocus className="min-h-12 rounded-2xl bg-[#E5484D] px-3 font-black text-white transition hover:bg-[#CF3D42] active:scale-[.98]">{confirmLabel}</button>
        </div>
      </section>
    </div>
  );
}
