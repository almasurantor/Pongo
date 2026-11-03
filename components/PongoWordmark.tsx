interface PongoWordmarkProps {
  className?: string;
  tone?: 'brand' | 'inverse';
}

export default function PongoWordmark({ className = '', tone = 'brand' }: PongoWordmarkProps) {
  return (
    <span className={`inline-flex items-center ${className}`} aria-label="Pongo">
      <span className="sr-only">Pongo</span>
      <span
        aria-hidden="true"
        className={`inline-flex items-center font-black leading-none tracking-[-0.055em] ${tone === 'inverse' ? 'text-white' : 'text-primary-purple dark:text-[#60A5FA]'}`}
      >
        <span>P</span>
        <span className="mx-[0.035em] inline-block h-[0.5em] w-[0.5em] shrink-0 translate-y-[0.09em] rounded-full bg-brand-orange shadow-[inset_-0.07em_-0.07em_0_rgba(194,65,12,0.22)]">
          <span className="ml-[0.115em] mt-[0.09em] block h-[0.105em] w-[0.105em] rounded-full bg-white/85" />
        </span>
        <span>ng</span>
        <span className="ml-[0.035em] inline-block h-[0.5em] w-[0.5em] shrink-0 translate-y-[0.09em] rounded-full bg-brand-orange shadow-[inset_-0.07em_-0.07em_0_rgba(194,65,12,0.22)]">
          <span className="ml-[0.115em] mt-[0.09em] block h-[0.105em] w-[0.105em] rounded-full bg-white/85" />
        </span>
      </span>
    </span>
  );
}
