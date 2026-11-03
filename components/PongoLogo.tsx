import Image from 'next/image';

type PongoLogoSize = 'sm' | 'md' | 'lg' | 'xl';

interface PongoLogoProps {
  alt?: string;
  className?: string;
  imageClassName?: string;
  priority?: boolean;
  size?: PongoLogoSize;
}

const sizeClasses: Record<PongoLogoSize, string> = {
  sm: 'h-9 w-9 rounded-lg',
  md: 'h-11 w-11 rounded-xl',
  lg: 'h-16 w-16 rounded-2xl',
  xl: 'h-20 w-20 rounded-2xl',
};

const imageSizes: Record<PongoLogoSize, number> = {
  sm: 36,
  md: 44,
  lg: 64,
  xl: 80,
};

export default function PongoLogo({
  alt = '',
  className = '',
  imageClassName = '',
  priority = false,
  size = 'md',
}: PongoLogoProps) {
  const pixels = imageSizes[size];

  return (
    <span className={`inline-flex shrink-0 items-center justify-center bg-[#2563EB] p-0.5 shadow-sm shadow-blue-950/15 ${sizeClasses[size]} ${className}`}>
      <Image
        src="/pongo.png"
        alt={alt}
        width={pixels}
        height={pixels}
        className={`h-full w-full object-contain ${imageClassName}`}
        priority={priority}
      />
    </span>
  );
}
