"""Tests ohne Netz:  python -m unittest -v  (im Ordner tools/reel_import)"""
import json
import unittest

import reel_import as r


class Ids(unittest.TestCase):
    def test_same_video_same_id(self):
        a = r.clip_id("https://www.instagram.com/reel/ABC123/?igsh=xyz&utm_source=ig")
        b = r.clip_id("instagram.com/reel/ABC123")
        self.assertEqual(a, b)
        self.assertRegex(a, r"^imp-[0-9a-f]{12}$")
        self.assertNotEqual(a, r.clip_id("https://www.instagram.com/reel/OTHER/"))

    def test_youtube_keeps_video_parameter(self):
        self.assertEqual(
            r.normalize_url("https://www.youtube.com/watch?v=abc&si=track&feature=share"),
            "https://youtube.com/watch?v=abc",
        )
        self.assertNotEqual(
            r.clip_id("https://youtube.com/watch?v=abc"),
            r.clip_id("https://youtube.com/watch?v=xyz"),
        )


class Frames(unittest.TestCase):
    def test_spread_over_duration(self):
        self.assertEqual(r.frame_times(40, 4), [5.0, 15.0, 25.0, 35.0])
        self.assertEqual(len(r.frame_times(8, None)), 4)    # mindestens 4
        self.assertEqual(len(r.frame_times(600, None)), 12)  # höchstens 12
        self.assertEqual(r.frame_times(0, None), [0.0])

    def test_stamp(self):
        self.assertEqual(r.stamp(0), "0:00")
        self.assertEqual(r.stamp(75.9), "1:15")


class ModelAnswer(unittest.TestCase):
    def test_plain_fenced_and_wrapped(self):
        want = {"exercises": []}
        self.assertEqual(r.extract_json('{"exercises": []}'), want)
        self.assertEqual(r.extract_json('```json\n{"exercises": []}\n```'), want)
        self.assertEqual(r.extract_json('Hier:\n{"exercises": []}\nFertig.'), want)
        with self.assertRaises(r.ImportError_):
            r.extract_json("keine Übungen gefunden")


class Exercises(unittest.TestCase):
    def norm(self, exercises, frames=6):
        return r.normalize_exercises({"exercises": exercises}, frames)

    def test_normalizes_category_tags_and_frames(self):
        out, notes = self.norm([{
            "name": " Cossack Squat ",
            "category": "Mobilität",
            "goals": ["beweglichkeit", "Beweglichkeit", "Hüftöffnung"],
            "equipment": "körpergewicht",
            "description": "Tief zur Seite absitzen.",
            "frames": [2, 2, 3],
        }])
        e = out[0]
        self.assertEqual(e["name"], "Cossack Squat")
        self.assertEqual(e["category"], "mobility")
        self.assertEqual(e["goals"], ["Beweglichkeit", "Hüftöffnung"])
        self.assertEqual(e["equipment"], ["Körpergewicht"])
        self.assertEqual(e["frames"], [2, 3])
        self.assertEqual(e["whenToUse"], "")
        self.assertEqual(notes, ["„Cossack Squat“: neues Schlagwort (Ziel) „Hüftöffnung“"])

    def test_rejects_broken_input(self):
        for bad, message in [
            ([{"category": "kraft"}], "name fehlt"),
            ([{"name": "A", "category": "cardio"}], "category"),
            ([{"name": "A", "category": "kraft", "frames": [6]}], "Standbild 6"),
            ([{"name": "A", "category": "kraft", "frames": ["1"]}], "Zahlen"),
            ([{"name": "A", "category": "kraft"}, {"name": "a", "category": "kraft"}], "doppelt"),
        ]:
            with self.assertRaises(r.ImportError_) as ctx:
                self.norm(bad)
            self.assertIn(message, str(ctx.exception))
        with self.assertRaises(r.ImportError_):
            r.normalize_exercises("text", 3)

    def test_limits_images_and_flags_missing_notes(self):
        out, notes = self.norm([{"name": "A", "category": "kraft", "frames": [0, 1, 2, 3, 4]}])
        self.assertEqual(out[0]["frames"], [0, 1, 2, 3])
        self.assertEqual(len(notes), 2)

    def test_accepts_bare_list_and_empty(self):
        self.assertEqual(r.normalize_exercises([], 0), ([], []))


class Prompt(unittest.TestCase):
    def test_contains_material_and_vocabulary(self):
        system, user = r.build_prompt({
            "title": "Hüft-Flow", "uploader": "coach_x", "caption": "3 Übungen",
            "transcript": "[0:03] Erst neunzig neunzig", "frames": [{"index": 0, "time": 3.0}],
        })
        self.assertIn("Maximalkraft", system)
        self.assertIn("Faszienrolle", system)
        self.assertIn("Nichts erfinden", system)
        for part in ("Hüft-Flow", "3 Übungen", "neunzig", "0 bei 0:03"):
            self.assertIn(part, user)


class Notes(unittest.TestCase):
    def test_clip_notes(self):
        text = r.clip_notes({
            "uploader": "coach_x", "caption": "Caption", "language": "de",
            "transcript": "[0:01] Hallo",
        })
        self.assertEqual(
            text, "Von: coach_x\n\nCaption\n\nTranskript (automatisch, de):\n[0:01] Hallo"
        )
        self.assertEqual(r.clip_notes({}), "")


class Taxonomy(unittest.TestCase):
    def test_file_is_well_formed(self):
        self.assertEqual(r.CATEGORIES, ("kraft", "physio", "mobility"))
        json.dumps(r.TAXONOMY)
        self.assertGreater(len(r.TAXONOMY["goals"]), 5)


if __name__ == "__main__":
    unittest.main()
