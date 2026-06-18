import { defineBackend } from '@aws-amplify/backend';
import { auth } from './auth/resource';
import { data } from './data/resource';
import { askExodus } from './functions/askExodus/resource';

/**
 * EXODUS Couples-in-Sync backend (Amplify Gen 2).
 * Deployed to the babysos AWS account (698387659425).
 */
defineBackend({
  auth,
  data,
  askExodus,
});
