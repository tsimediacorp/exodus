import { type ClientSchema, a, defineData } from '@aws-amplify/backend';
import { askExodus } from '../functions/askExodus/resource';

/**
 * Confidentiality model:
 *  - Message.members holds the userIds allowed to read a message.
 *      private message  -> members = [authorId]            (author only)
 *      shared message   -> members = [partnerA, partnerB]  (both)
 *    Enforced by `ownersDefinedIn('members')`, so the data layer itself keeps
 *    one partner's private messages off the other's device.
 *  - The askExodus function reads across both partners server-side (elevated
 *    access) to counsel wisely without leaking private content.
 */
const schema = a.schema({
  UserProfile: a
    .model({
      displayName: a.string(),
      email: a.string(),
      coupleId: a.string(),
    })
    .authorization((allow) => [allow.owner()]),

  Couple: a
    .model({
      member1Id: a.string().required(),
      member2Id: a.string(),
      inviteCode: a.string(),
      members: a.string().array(),
      messages: a.hasMany('Message', 'coupleId'),
    })
    .authorization((allow) => [allow.ownersDefinedIn('members'), allow.owner()]),

  Message: a
    .model({
      coupleId: a.id().required(),
      couple: a.belongsTo('Couple', 'coupleId'),
      authorId: a.string().required(),
      role: a.enum(['user', 'exodus']),
      text: a.string().required(),
      visibility: a.enum(['private', 'shared']),
      members: a.string().array(),
    })
    .authorization((allow) => [allow.ownersDefinedIn('members')]),

  // ---- Gamification ----
  QuizRound: a
    .model({
      coupleId: a.id().required(),
      day: a.date().required(),
      prompt: a.string().required(),
      members: a.string().array(),
      answers: a.hasMany('QuizAnswer', 'roundId'),
    })
    .authorization((allow) => [allow.ownersDefinedIn('members')]),

  QuizAnswer: a
    .model({
      roundId: a.id().required(),
      round: a.belongsTo('QuizRound', 'roundId'),
      authorId: a.string().required(),
      answer: a.string().required(),
      members: a.string().array(),
    })
    .authorization((allow) => [allow.ownersDefinedIn('members')]),

  DailyAlignment: a
    .model({
      coupleId: a.id().required(),
      day: a.date().required(),
      score: a.integer().required(),
      recap: a.string(),
      members: a.string().array(),
    })
    .authorization((allow) => [allow.ownersDefinedIn('members')]),

  // ---- Server-side counseling (confidential cross-partner) ----
  askExodus: a
    .mutation()
    .arguments({
      coupleId: a.string().required(),
      text: a.string().required(),
      visibility: a.string().required(), // 'private' | 'shared'
    })
    .returns(a.string())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(askExodus)),
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: 'userPool',
  },
});
