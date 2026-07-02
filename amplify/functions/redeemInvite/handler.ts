import type { Schema } from '../../data/resource';
import { env } from '$amplify/env/redeemInvite';
import { Amplify } from 'aws-amplify';
import { generateClient } from 'aws-amplify/data';
import { getAmplifyDataClientConfig } from '@aws-amplify/backend/function/runtime';

const { resourceConfig, libraryOptions } = await getAmplifyDataClientConfig(env);
Amplify.configure(resourceConfig, libraryOptions);
const client = generateClient<Schema>();

/**
 * Redeem an invite code: add the caller as the second member of the couple.
 * Returns the coupleId on success, or an empty string if the code is invalid
 * or already fully paired.
 */
export const handler: Schema['redeemInvite']['functionHandler'] = async (event) => {
  const code = event.arguments.inviteCode?.trim();
  const callerId = (event.identity as { sub?: string } | undefined)?.sub;
  if (!code || !callerId) return '';

  const { data: matches } = await client.models.Couple.list({
    filter: { inviteCode: { eq: code } },
    limit: 1,
  });
  const couple = matches?.[0];
  if (!couple) return '';
  if (couple.member2Id && couple.member2Id !== callerId) return ''; // already paired
  if (couple.member1Id === callerId) return couple.id; // can't pair with yourself

  await client.models.Couple.update({
    id: couple.id,
    member2Id: callerId,
    members: [couple.member1Id, callerId],
  });

  return couple.id;
};
