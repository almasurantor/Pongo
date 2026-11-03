'use client';

import { usePathname } from 'next/navigation';
import Navbar from './Navbar';

export default function ConditionalNavbar() {
  const pathname = usePathname();
  
  // Don't show navbar on homepage, login, or signup pages
  if (pathname === '/' || pathname === '/landing' || pathname === '/login' || pathname === '/signup') {
    return null;
  }
  
  return <Navbar />;
}
