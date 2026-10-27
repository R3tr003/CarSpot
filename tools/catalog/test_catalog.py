"""Test delle regole pure della pipeline: python3 -I -m unittest tools/catalog/test_catalog.py"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_catalog import (body_type, clean_company, is_excluded, merge_generations,  # noqa: E402
                           split_homonyms, strip_generation, strip_make)
from catalog_common import normalize, slug  # noqa: E402


def item(starts, ends=(), images=(), sitelinks=10, itwiki=True):
    return {"starts": list(starts), "ends": list(ends), "images": list(images), "sitelinks": sitelinks,
            "itwiki": itwiki, "dewiki": False, "frwiki": False}


class TestText(unittest.TestCase):
    def test_slug(self):
        self.assertEqual(slug("Alfa Romeo"), "alfa-romeo")
        self.assertEqual(slug("Citroën ë-C4"), "citroen-e-c4")

    def test_normalize(self):
        self.assertEqual(normalize("  Dobló "), "doblo")
        self.assertEqual(normalize("Mercedes-Benz  Classe A"), "mercedes benz classe a")

    def test_strip_generation(self):
        self.assertEqual(strip_generation("Volkswagen Golf Mk7"), "Volkswagen Golf")
        self.assertEqual(strip_generation("Fiat 500 (2007)"), "Fiat 500")
        self.assertEqual(strip_generation("BMW 3 Series (E46)"), "BMW 3 Series")
        self.assertEqual(strip_generation("Renault Clio IV"), "Renault Clio")
        self.assertEqual(strip_generation("Toyota Corolla twelfth generation"), "Toyota Corolla twelfth generation")
        self.assertEqual(strip_generation("Citroën C3"), "Citroën C3")

    def test_strip_make(self):
        self.assertEqual(strip_make("Volkswagen Golf", "Volkswagen"), "Golf")
        self.assertEqual(strip_make("Mercedes-Benz Classe A", "Mercedes-Benz"), "Classe A")
        self.assertEqual(strip_make("Golf", "Volkswagen"), "Golf")

    def test_clean_company(self):
        self.assertEqual(clean_company("Ferrari S.p.A."), "Ferrari")
        self.assertEqual(clean_company("AB Volvo"), "Volvo")
        self.assertEqual(clean_company("British Motor Corporation"), "British Motor Corporation")


class TestVariants(unittest.TestCase):
    def test_variant_suffix(self):
        from build_catalog import variant_suffix_ok
        self.assertTrue(variant_suffix_ok("Golf GTI", "Golf"))
        self.assertFalse(variant_suffix_ok("128 Mk1 Sedan", "128"))
        self.assertFalse(variant_suffix_ok("Ducato (third generation) Facelift 2014", "Ducato"))
        self.assertFalse(variant_suffix_ok("F15", "X5"))
        self.assertFalse(variant_suffix_ok("Citroën Synergie", "Ulysse"))

    def test_curated_name(self):
        from build_catalog import curated_variant_name
        self.assertEqual(curated_variant_name("Golf", "GTI"), "Golf GTI")
        self.assertEqual(curated_variant_name("Serie 2", "=M2"), "M2")


class TestYears(unittest.TestCase):
    def test_description(self):
        from build_catalog import years_from_description
        self.assertEqual(years_from_description("autovettura del 1996 prodotta dalla Audi"), (1996, None))
        self.assertEqual(years_from_description("car produced by Alfa Romeo from 2000 to 2010"), (2000, 2010))
        self.assertEqual(years_from_description("car manufactured between 2005 and 2011"), (2005, 2011))
        self.assertEqual(years_from_description("570 hp"), (None, None))


class TestRules(unittest.TestCase):
    labels = {"Q1": "concept car", "Q2": "sport utility vehicle", "Q3": "car model", "Q4": "c-segment"}

    def test_excluded(self):
        self.assertTrue(is_excluded(["Q1"], self.labels))
        self.assertFalse(is_excluded(["Q3", "Q4"], self.labels))

    def test_body(self):
        self.assertEqual(body_type(["Q2", "Q3"], self.labels), "suv")
        self.assertEqual(body_type(["Q4"], self.labels), "berlina")

    def test_merge_generations(self):
        merged = merge_generations([item([1997], [2003], ["a.jpg"]), item([2019], [], ["b.jpg"], 40)])
        self.assertEqual(merged["yearStart"], 1997)
        self.assertIsNone(merged["yearEnd"])
        self.assertEqual(merged["image"], "b.jpg")
        self.assertEqual(merged["popularity"], 40)

    def test_split_homonyms(self):
        clusters = split_homonyms([item([2007]), item([1957], [1975])])
        self.assertEqual(len(clusters), 2)
        self.assertEqual(split_homonyms([item([2008], [2012]), item([2012])]).__len__(), 1)


if __name__ == "__main__":
    unittest.main()
