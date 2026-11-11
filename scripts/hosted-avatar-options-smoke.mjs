import { randomBytes } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { createClient } from '@supabase/supabase-js';

const expectedRef = 'dqkmtbrzhqearrqpmlwd';
const expectedUrl = `https://${expectedRef}.supabase.co`;
const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').replace(/\/$/, '');
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (process.env.PONGO_ALLOW_HOSTED_AVATAR_TEST !== 'YES_CREATE_RESTORE_DELETE_ONE_TEST_USER') {
  throw new Error('Set PONGO_ALLOW_HOSTED_AVATAR_TEST=YES_CREATE_RESTORE_DELETE_ONE_TEST_USER.');
}
if (url !== expectedUrl) throw new Error(`Refusing target ${url || '(missing URL)'}; expected ${expectedUrl}.`);
if (!anonKey || !serviceRoleKey) throw new Error('The hosted anon and service-role keys are required.');

const admin = createClient(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const client = createClient(url, anonKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const suffix = `${Date.now()}${randomBytes(3).toString('hex')}`;
const email = `avatar-release-${suffix}@pongo.test`;
const password = `Pongo-${randomBytes(24).toString('base64url')}!9a`;
const displayName = `AvatarSmoke${suffix.slice(-6)}`;
const originalAvatar = {
  version: 1,
  fur: 'brown',
  hat: 'baseball-cap',
  glasses: 'round',
  facialHair: 'mustache',
  expression: 'confident',
  accessory: 'headphones',
};
const expandedAvatar = {
  version: 1,
  fur: 'rainbow',
  hat: 'wizard-hat',
  glasses: 'heart',
  facialHair: 'curled-mustache',
  expression: 'angry',
  accessory: 'gold-chain',
};

const sameJson = (left, right) => isDeepStrictEqual(left, right);
let userId;
let signedIn = false;
let rpcSaved = false;
let rpcRestored = false;
let cleanupComplete = false;

try {
  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName, avatar_release_fixture: true },
  });
  if (created.error || !created.data.user) {
    throw new Error(`Could not create avatar release fixture: ${created.error?.message}`);
  }
  userId = created.data.user.id;

  const seeded = await admin.from('profiles')
    .update({ avatar_config: originalAvatar })
    .eq('id', userId)
    .select('id,avatar_config')
    .single();
  if (seeded.error || !sameJson(seeded.data?.avatar_config, originalAvatar)) {
    throw new Error(`Could not seed the fixture's legacy avatar: ${seeded.error?.message}`);
  }

  const auth = await client.auth.signInWithPassword({ email, password });
  if (auth.error || !auth.data.session?.access_token) {
    throw new Error(`Could not authenticate avatar release fixture: ${auth.error?.message}`);
  }
  signedIn = true;

  const authenticatedUser = await client.auth.getUser();
  if (authenticatedUser.error || authenticatedUser.data.user?.id !== userId) {
    throw new Error(`Authenticated session verification failed: ${authenticatedUser.error?.message}`);
  }

  const before = await client.from('profiles').select('id,avatar_config').eq('id', userId).single();
  if (before.error || !sameJson(before.data?.avatar_config, originalAvatar)) {
    throw new Error(`Existing avatar did not load through the authenticated API: ${before.error?.message}`);
  }

  const saved = await client.rpc('update_my_avatar_v1', { p_avatar_config: expandedAvatar });
  if (saved.error || !sameJson(saved.data, expandedAvatar)) {
    throw new Error(`Expanded avatar RPC failed: ${saved.error?.message}`);
  }
  const afterSave = await client.from('profiles').select('avatar_config').eq('id', userId).single();
  if (afterSave.error || !sameJson(afterSave.data?.avatar_config, expandedAvatar)) {
    throw new Error(`Expanded avatar did not persist: ${afterSave.error?.message}`);
  }
  rpcSaved = true;

  const restored = await client.rpc('update_my_avatar_v1', { p_avatar_config: originalAvatar });
  if (restored.error || !sameJson(restored.data, originalAvatar)) {
    throw new Error(`Avatar restore RPC failed: ${restored.error?.message}`);
  }
  const afterRestore = await client.from('profiles').select('avatar_config').eq('id', userId).single();
  if (afterRestore.error || !sameJson(afterRestore.data?.avatar_config, originalAvatar)) {
    throw new Error(`Restored avatar did not persist: ${afterRestore.error?.message}`);
  }
  rpcRestored = true;
} finally {
  if (userId) {
    if (!rpcRestored) {
      const fallbackRestore = await admin.from('profiles')
        .update({ avatar_config: originalAvatar })
        .eq('id', userId)
        .select('avatar_config')
        .single();
      if (fallbackRestore.error || !sameJson(fallbackRestore.data?.avatar_config, originalAvatar)) {
        throw new Error(`Fixture fallback restore failed: ${fallbackRestore.error?.message}`);
      }
    }
    const deleted = await admin.auth.admin.deleteUser(userId, false);
    if (deleted.error) throw new Error(`Avatar release fixture cleanup failed: ${deleted.error.message}`);
    const remaining = await admin.from('profiles').select('id').eq('id', userId);
    if (remaining.error || remaining.data.length !== 0) {
      throw new Error(`Avatar release fixture profile cleanup failed: ${remaining.error?.message}`);
    }
    cleanupComplete = true;
  }
}

console.log(JSON.stringify({
  target: expectedRef,
  authenticated_session: signedIn,
  existing_avatar_loaded: true,
  expanded_avatar_saved_by_rpc: rpcSaved,
  original_avatar_restored_by_rpc: rpcRestored,
  disposable_fixture_removed: cleanupComplete,
}, null, 2));
