/// In what order the 自定义 passages of the open group are read.
///
/// The unit that moves is the whole article: a shuffled run still reads every
/// article from its first sentence to its last, it only changes which article
/// comes next.
enum PlaybackOrder {
  sequential('顺序'),
  shuffle('随机');

  const PlaybackOrder(this.label);

  final String label;

  static PlaybackOrder fromName(String? name) {
    for (final order in values) {
      if (order.name == name) return order;
    }
    return sequential;
  }
}
