import '../models/journey.dart';

/// The guided plans on offer. Static by design — these are curated arcs, not
/// generated ones; only the day-by-day content is written per couple.
class JourneyCatalog {
  static const List<Journey> all = [
    Journey(
      id: 'conflict-7',
      title: 'Fighting Fair',
      subtitle: '7 days on conflict that draws you closer',
      theme:
          'Handling conflict in marriage God\'s way: listening before answering, '
          'being slow to anger, repenting quickly, refusing contempt and the '
          'silent treatment, forgiving as Christ forgave, and learning to fight '
          'the problem instead of each other.',
      totalDays: 7,
    ),
    Journey(
      id: 'money-14',
      title: 'One Purse',
      subtitle: '14 days on money, generosity, and trust',
      theme:
          'Money in marriage: stewardship over ownership, honesty about spending, '
          'contentment against comparison, generosity and tithing, getting free of '
          'debt, planning together, and refusing to let provision become an idol '
          'or a weapon between spouses.',
      totalDays: 14,
    ),
    Journey(
      id: 'intimacy-10',
      title: 'Naked and Unashamed',
      subtitle: '10 days on intimacy God designed',
      theme:
          'Intimacy in marriage as God designed it: sex as covenant celebration '
          'rather than transaction, emotional nakedness without shame, guarding '
          'the marriage bed, purity of the eyes and heart, communicating desire '
          'and difficulty honestly, and pursuing one another rather than settling '
          'into roommates.',
      totalDays: 10,
    ),
    Journey(
      id: 'trust-14',
      title: 'Rebuilding Trust',
      subtitle: '14 days for after the breach',
      theme:
          'Rebuilding trust after it has been broken — by betrayal, deception, '
          'or a long pattern of small letdowns. Genuine repentance versus mere '
          'apology, the difference between forgiveness and restored trust, '
          'bearing consequences without resentment, rebuilding through consistency '
          'over time, and hope grounded in God\'s power to restore.',
      totalDays: 14,
    ),
    Journey(
      id: 'prayer-7',
      title: 'Praying Together',
      subtitle: '7 days to build a habit that lasts',
      theme:
          'Learning to pray together as a couple: overcoming the awkwardness of '
          'praying out loud, praying scripture, praying for each other rather than '
          'at each other, building a sustainable daily rhythm, and praying through '
          'decisions and hard seasons as one.',
      totalDays: 7,
    ),
    Journey(
      id: 'newlywed-21',
      title: 'The First Year',
      subtitle: '21 days of foundations for newlyweds',
      theme:
          'Foundations for a new marriage: leaving and cleaving, setting boundaries '
          'with family and friends, merging two ways of living, expectations versus '
          'reality, roles and servant leadership, building spiritual habits early, '
          'and establishing patterns that will hold for decades.',
      totalDays: 21,
    ),
  ];

  static Journey? byId(String id) {
    for (final j in all) {
      if (j.id == id) return j;
    }
    return null;
  }
}
