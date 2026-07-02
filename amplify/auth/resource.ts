import { defineAuth } from '@aws-amplify/backend';

/**
 * Cognito auth for EXODUS accounts. Email/password to start.
 *
 * The sign-up confirmation email is customized to (a) carry the Cognito
 * verification code and (b) hand founding members their Bonus Card 2 code.
 * NOTE: this is currently sent to every new sign-up (the launch cohort = the
 * founding members). When a later non-founding cohort exists, gate the bonus
 * code with a CustomMessage Lambda trigger instead.
 *
 * Sign in with Apple is a planned follow-up — it needs Apple Developer secrets
 * (Service ID, Key ID, Team ID, private key) set via `ampx sandbox secret`,
 * so it's intentionally not wired here yet to keep the first deploy unblocked.
 */
export const auth = defineAuth({
  loginWith: {
    email: {
      verificationEmailStyle: 'CODE',
      verificationEmailSubject: 'Welcome to EXODUS — confirm your account',
      verificationEmailBody: (createCode) =>
        `Welcome to EXODUS — God's design. Unfiltered.\n\n` +
        `Your confirmation code is ${createCode()}. Enter it in the app to ` +
        `activate your account.\n\n` +
        `As a founding member, here is your Bonus Card 2 code:\n\n` +
        `    CRC20Aurora\n\n` +
        `Walk in His design.\n— EXODUS`,
    },
  },
  userAttributes: {
    preferredUsername: { required: false, mutable: true },
  },
});
