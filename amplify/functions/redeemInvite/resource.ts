import { defineFunction } from '@aws-amplify/backend';

/**
 * Pairing needs elevated access: the joining partner is not yet a member of the
 * couple, so client-side auth (ownersDefinedIn members) can't let them read or
 * update it. This function runs server-side to look up the invite code and add
 * the joiner to the couple.
 */
export const redeemInvite = defineFunction({
  name: 'redeemInvite',
  entry: './handler.ts',
  timeoutSeconds: 30,
});
