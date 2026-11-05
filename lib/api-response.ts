import { NextResponse } from 'next/server';

export async function readJsonObject(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const body: unknown = await request.json();
    return body !== null && typeof body === 'object' && !Array.isArray(body)
      ? body as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

export function invalidJsonResponse() {
  return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
}

export function apiError(error: unknown, fallback = 'Request failed') {
  const message = error && typeof error === 'object' && 'message' in error
    ? String((error as { message: unknown }).message)
    : fallback;
  const normalized = message.toLowerCase();
  const status = normalized.includes('not found') ? 404
    : normalized.includes('expired') || normalized.includes('already closed') ? 410
      : normalized.includes('unauthorized') || normalized.includes('restricted') || normalized.includes('admin access required') ? 403
        : normalized.includes('already') || normalized.includes('limit') || normalized.includes('active ranked') || normalized.includes('only an active') ? 409
          : 400;
  return NextResponse.json({ error: message }, { status });
}
