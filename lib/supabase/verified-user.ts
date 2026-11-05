import { headers } from 'next/headers';

export const VERIFIED_USER_HEADER = 'x-pongo-verified-user';

// Middleware overwrites this internal header after auth.getUser() succeeds.
// Client-supplied values are removed before the request reaches a page.
export async function getVerifiedUserId() {
  return (await headers()).get(VERIFIED_USER_HEADER);
}
