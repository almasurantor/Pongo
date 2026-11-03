import { createClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

export async function GET(request: Request) {
  const requestUrl = new URL(request.url)
  const code = requestUrl.searchParams.get('code')
  const providerError = requestUrl.searchParams.get('error_description')
  const requestedNext = requestUrl.searchParams.get('next')
  const next = requestedNext?.startsWith('/') && !requestedNext.startsWith('//') ? requestedNext : '/dashboard'
  const origin = requestUrl.origin

  if (providerError) {
    const login = new URL('/login', origin)
    login.searchParams.set('error', providerError)
    return NextResponse.redirect(login)
  }

  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (error) {
      const login = new URL('/login', origin)
      login.searchParams.set('error', 'The sign-in link is invalid or expired. Please try again.')
      return NextResponse.redirect(login)
    }
  }

  return NextResponse.redirect(new URL(next, origin))
}
