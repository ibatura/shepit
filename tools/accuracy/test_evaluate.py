import unittest

from evaluate import latin_hit_rate, normalize, parse_bench, parse_engine, wer


class NormalizeTest(unittest.TestCase):
    def test_lowercases_and_strips_punctuation(self):
        self.assertEqual(normalize("Привіт, GitHub!"), ["привіт", "github"])

    def test_keeps_apostrophe_inside_ukrainian_words(self):
        self.assertEqual(normalize("Я з’їв м'ясо"), ["я", "з'їв", "м'ясо"])

    def test_empty(self):
        self.assertEqual(normalize("  ...  "), [])


class WerTest(unittest.TestCase):
    def test_identical(self):
        self.assertEqual(wer(["a", "b"], ["a", "b"]), 0.0)

    def test_one_substitution_of_four(self):
        self.assertEqual(wer(["a", "b", "c", "d"], ["a", "x", "c", "d"]), 0.25)

    def test_insertion_and_deletion(self):
        self.assertAlmostEqual(wer(["a", "b", "c"], ["a", "c", "d", "e"]), 1.0)

    def test_empty_reference(self):
        self.assertEqual(wer([], ["a"]), 1.0)
        self.assertEqual(wer([], []), 0.0)


class LatinHitRateTest(unittest.TestCase):
    def test_counts_latin_words_found_in_hypothesis(self):
        ref = normalize("Відкрив pull request у GitHub")
        hyp = normalize("відкрив пул request у GitHub")
        self.assertEqual(latin_hit_rate(ref, hyp), (2, 3))

    def test_repeated_terms_count_separately(self):
        ref = normalize("commit і ще commit")
        hyp = normalize("commit і ще коміт")
        self.assertEqual(latin_hit_rate(ref, hyp), (1, 2))

    def test_no_latin_words(self):
        self.assertEqual(latin_hit_rate(["привіт"], ["привіт"]), (0, 0))


class BenchOutputTest(unittest.TestCase):
    def test_parse_bench_output(self):
        lines = [
            '{"engine":"whisperkit","event":"load","model":"large-v3","residentMB":3100,"seconds":2.5}',
            '{"audioSeconds":8.7,"event":"result","file":"/x/recordings/01.wav","language":null,"seconds":1.2,"text":"текст"}',
            '{"audioSeconds":5.0,"event":"result","file":"/x/recordings/02.wav","language":"uk","seconds":0.8,"text":"ще"}',
        ]
        self.assertEqual(parse_bench(lines), {
            "load_s": 2.5, "resident_mb": 3100,
            "results": [("01.wav", "текст", 1.2), ("02.wav", "ще", 0.8)]})

    def test_error_line_raises(self):
        with self.assertRaises(RuntimeError):
            parse_bench(['{"event":"error","message":"modelMissing"}'])

    def test_missing_output_raises(self):
        with self.assertRaises(RuntimeError):
            parse_bench([])

    def test_engine_spec(self):
        self.assertEqual(parse_engine("apple"), ("apple", ""))
        self.assertEqual(parse_engine("whisperkit:large-v3"), ("whisperkit", "large-v3"))


if __name__ == "__main__":
    unittest.main()
