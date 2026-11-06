import { describe, expect, it } from 'vitest';
import { authErrorMessage } from './auth-errors';

describe('authErrorMessage', () => {
  it('turns provider errors into actionable messages', () => {
    expect(authErrorMessage(new Error('Invalid login credentials'))).toBe('Email or password is incorrect.');
    expect(authErrorMessage(new Error('User already registered'))).toContain('reset your password');
    expect(authErrorMessage(new Error('Failed to fetch'))).toContain('Check your connection');
    expect(authErrorMessage(new DOMException('Request timed out', 'TimeoutError'))).toContain('Check your connection');
  });
});
