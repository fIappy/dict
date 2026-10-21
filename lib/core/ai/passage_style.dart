/// The voice the reader wants for a generated passage. The label is what the
/// UI shows; the prompt is what the model is told.
enum PassageStyle {
  descriptive(
    '描述型',
    'Descriptive narrative: build the scene from concrete sensory detail and a '
        'steady point of view; let description carry the meaning.',
  ),
  explanatory(
    '科普型',
    'Explanatory science writing for a curious general reader: explain how and '
        'why something works, one idea at a time, with precise but plain words.',
  ),
  humorous(
    '幽默型',
    'Humorous: dry wit, unexpected turns and comic timing. Never slapstick, '
        'never explain the joke.',
  ),
  mystery(
    '悬疑型',
    'Mystery and suspense: withhold one key fact, tighten the tension line by '
        'line, and end on an unresolved beat.',
  ),
  news(
    '新闻式',
    'News report: inverted pyramid, factual and attributed voice, no opinion, '
        'concrete numbers and names.',
  ),
  dialogue(
    '多人对话式',
    'Multi-speaker dialogue: two to four named speakers taking turns, natural '
        'interruptions and overlaps, no narration blocks longer than one line.',
  );

  const PassageStyle(this.label, this.prompt);

  final String label;
  final String prompt;

  static PassageStyle byName(String? name) => values.firstWhere(
        (style) => style.name == name,
        orElse: () => PassageStyle.descriptive,
      );
}
