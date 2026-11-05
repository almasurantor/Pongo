'use client';

import dynamic from 'next/dynamic';
import { usePathname } from 'next/navigation';

const Navbar = dynamic(() => import('./Navbar'));
const MatchResultPopup = dynamic(() => import('./MatchResultPopup'));

export default function ConditionalNavbar() {
  const pathname = usePathname();
  
  // Don't show navbar on homepage, login, or signup pages
  if (pathname === '/' || pathname === '/landing' || pathname === '/login' || pathname === '/signup') {
    return null;
  }
  
  return <><Navbar /><MatchResultPopup /></>;
}
