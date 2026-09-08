/**
 * Notification payload prefixes.
 *
 * Mirrors NotificationService in the app. Kept as constants on both sides
 * because a typo here is a tap that silently lands on the wrong screen, which
 * is exactly the bug that sent every check-in notification to the devotional
 * tab for weeks.
 */
export const NotificationPayloads = {
  devotional: 'devotional',
  checkIn: 'checkin:',
  chat: 'chat:',
} as const;
