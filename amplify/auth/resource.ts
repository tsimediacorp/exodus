import { defineAuth } from '@aws-amplify/backend';

/**
 * Cognito auth for EXODUS accounts. Email/password to start.
 *
 * Sign in with Apple is a planned follow-up — it needs Apple Developer secrets
 * (Service ID, Key ID, Team ID, private key) set via `ampx sandbox secret`,
 * so it's intentionally not wired here yet to keep the first deploy unblocked.
 */
export const auth = defineAuth({
  loginWith: {
    email: true,
  },
  userAttributes: {
    preferredUsername: { required: false, mutable: true },
  },
});
