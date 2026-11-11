import 'package:flutter/widgets.dart';

/// How much room EXODUS has, decided by width alone.
///
/// iPhone Duo is the reason this exists. Folded, its outer screen is an
/// ordinary phone (about 466pt wide). Unfolded, the inner screen is about
/// 669 x 951pt with regular size classes in both directions, which is closer
/// to a small iPad than to a phone. The same app has to be right on both, and
/// has to move between them while someone is mid-sentence.
///
/// Width, never orientation. Apple is explicit that the inner display does not
/// honour an app's supported orientations, so an orientation check would be
/// answering the wrong question. The same rule makes iPad and Split View
/// behave without any extra code.
enum ExodusWidth {
  /// One column, bottom bar. Every iPhone, and the Duo folded.
  compact,

  /// Rail, side-by-side panes, facing pages. The Duo unfolded, and iPad.
  expanded,
}

class ExodusLayout {
  ExodusLayout._();

  /// The line between the two. 600pt clears every phone in portrait or
  /// landscape-on-the-outer-screen by a wide margin, and sits well under the
  /// Duo's inner width, so neither screen sits near the edge and flickers.
  static const double expandedMinWidth = 600;

  /// Space left either side of the centre of a two-pane layout.
  ///
  /// When the Duo is partly open, Apple describes a folding region down the
  /// middle that content should not sit in. Flutter cannot see that region
  /// yet, so anything split into two panes keeps its centre clear by design
  /// rather than by measurement.
  static const double centreGutter = 28;

  /// Below this, an expanded screen still shows one content pane at a time.
  ///
  /// The Duo's inner screen held upright is 669pt: after the rail, that is
  /// one generous column, and splitting it would leave a thread narrower
  /// than the folded phone. Held sideways it is 951pt, which comfortably
  /// fits a list beside a thread. So the split follows the width you
  /// actually have, not the device you are holding.
  static const double twoPaneMinWidth = 880;

  static bool hasRoomForTwoPanes(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= twoPaneMinWidth;

  static ExodusWidth widthOf(BuildContext context) =>
      classify(MediaQuery.sizeOf(context).width);

  static ExodusWidth classify(double width) =>
      width >= expandedMinWidth ? ExodusWidth.expanded : ExodusWidth.compact;

  static bool isExpanded(BuildContext context) =>
      widthOf(context) == ExodusWidth.expanded;

  /// Whether the user has asked the system for less motion. Every flourish
  /// added for the large screen checks this first.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
