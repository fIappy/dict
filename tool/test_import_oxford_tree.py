import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import import_oxford_tree as ox  # noqa: E402


class DecodeShiftedTests(unittest.TestCase):
    def test_preserves_literal_space_and_decodes_shifted_ascii(self) -> None:
        # 0x03 -> space, 0x20 -> space (must NEVER shift to '='), 0x0A -> "'"
        raw = chr(0x2E) + 'H' + chr(0x52) + ' ' + chr(0x20) + chr(0x4C) + chr(0x0A) + 'P'
        # 0x2e+29 = 75 ('K'), 'H' (72)->101 ('e'), 0x52+29=111 ('o'? wait: let's test direct known codepoints)
        # 'K' = 75 -> 46 (0x2E), 'e' = 101 -> 72 (0x48), 'n' = 110 -> 81 (0x51), 'y' = 121 -> 92 (0x5C)
        sample = ''.join(chr(ord(c) - 29) for c in 'Kenny') + ' ' + ''.join(chr(ord(c) - 29) for c in "is'ok")
        self.assertEqual(ox.decode_shifted(sample, check_unknown=True), "Kenny is'ok")

    def test_decodes_special_glyphs_and_café(self) -> None:
        raw = '\x7e1Cafe'  # dummy control check via actual codepoints below
        sample = '\u07e1Caf\u00a9\u07d9ok\u07e8\u07e2'
        # Shift ASCII part 'Caf', 'ok' by -29
        encoded = '\u07e1' + ''.join(chr(ord(c) - 29) for c in 'Caf') + '\u00a9' + '\u07d9' + ''.join(chr(ord(c) - 29) for c in 'ok') + '\u07e8\u07e2'
        self.assertEqual(ox.decode_shifted(encoded, check_unknown=True), '"Café — ok..."')

    def test_smart_title_case_handles_acronyms_apostrophes_and_numbers(self) -> None:
        self.assertEqual(ox.smart_title_case('POLICE TV'), 'Police TV')
        self.assertEqual(ox.smart_title_case('1 THE JOGGER'), '1 The Jogger')
        self.assertEqual(ox.smart_title_case("DEAD MAN'S MONEY"), "Dead Man's Money")
        self.assertEqual(ox.smart_title_case('NEW YORK CAFÉ'), 'New York Café')

    def test_dehyphenation_keeps_stutter_and_rejoins_word_wraps(self) -> None:
        self.assertEqual(ox.join_text_pair('Ding-', 'dong!'), 'Ding-dong!')
        self.assertEqual(ox.join_text_pair('G-', 'g-give'), 'G-g-give')
        self.assertEqual(ox.join_text_pair('the win-', 'dow.'), 'the window.')

    def test_fnv1a_matches_custom_home_meta_algorithm(self) -> None:
        self.assertEqual(ox.fnv1a_32_utf16('abc'), '1a47e90b')


if __name__ == '__main__':
    unittest.main()
