import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { authRedirectForPath } from '@/lib/auth-routing'
import { VERIFIED_USER_HEADER } from '@/lib/supabase/verified-user'
import { AUTH_FETCH_TIMEOUT_MS, createFetchWithTimeout } from '@/lib/fetch-with-timeout'

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({
    request,
  })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      global: { fetch: createFetchWithTimeout(AUTH_FETCH_TIMEOUT_MS) },
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({
            request,
          })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // IMPORTANT: Avoid writing any logic between createServerClient and
  // supabase.auth.getUser(). A simple mistake could make it so that the
  // middleware and Server Components read different session values.

  let user = null
  try {
    const result = await supabase.auth.getUser()
    user = result.data.user
  } catch {
    // A failed or timed-out auth service must not strand an installed app on
    // a blank launch. Treat this request as unverified without deleting the
    // stored session; the next navigation can verify it again.
  }

  // Pages can reuse the identity that middleware just verified instead of
  // making a second auth network request. Never trust an incoming copy.
  const refreshedCookies = supabaseResponse.cookies.getAll()
  const verifiedHeaders = new Headers(request.headers)
  verifiedHeaders.delete(VERIFIED_USER_HEADER)
  if (user) verifiedHeaders.set(VERIFIED_USER_HEADER, user.id)
  const cookieHeader = request.cookies.toString()
  if (cookieHeader) verifiedHeaders.set('cookie', cookieHeader)
  supabaseResponse = NextResponse.next({ request: { headers: verifiedHeaders } })
  refreshedCookies.forEach((cookie) => supabaseResponse.cookies.set(cookie))

  const redirectWithSessionCookies = (pathname: string) => {
    const url = request.nextUrl.clone()
    url.pathname = pathname
    url.search = ''
    const response = NextResponse.redirect(url)
    supabaseResponse.cookies.getAll().forEach((cookie) => response.cookies.set(cookie))
    return response
  }

  const authRedirect = authRedirectForPath(request.nextUrl.pathname, !!user)
  if (authRedirect) return redirectWithSessionCookies(authRedirect)

  // IMPORTANT: You *must* return the supabaseResponse object as it is. If you're
  // creating a new response object with NextResponse.next() make sure to:
  // 1. Pass the request in it, like so:
  //    const myNewResponse = NextResponse.next({ request })
  // 2. Copy over the cookies, like so:
  //    myNewResponse.cookies.setAll(supabaseResponse.cookies.getAll())
  // 3. Change the myNewResponse object to fit your needs, but avoid changing
  //    the cookies!
  // 4. Finally:
  //    return myNewResponse
  // If this is not done, you may be causing the browser and server to go out
  // of sync and terminate the user's session prematurely.

  return supabaseResponse
}
