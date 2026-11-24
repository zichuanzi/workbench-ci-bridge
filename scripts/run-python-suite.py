"""Run the full Python suite and identify failures by discovery order."""

from __future__ import annotations

import argparse
import sys
import unittest
from pathlib import Path


def test_cases(suite: unittest.TestSuite):
    for entry in suite:
        if isinstance(entry, unittest.TestSuite):
            yield from test_cases(entry)
        else:
            yield entry


class CaseNumberResult(unittest.TextTestResult):
    def __init__(self, stream, descriptions, verbosity, *, case_numbers):
        super().__init__(stream, descriptions, verbosity)
        self.case_numbers = case_numbers
        self.failed_cases: set[int] = set()

    def report_case(self, case):
        self.failed_cases.add(self.case_numbers.get(id(case), 0))

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.report_case(test)

    def addError(self, test, err):
        super().addError(test, err)
        self.report_case(test)

    def addSubTest(self, test, subtest, err):
        super().addSubTest(test, subtest, err)
        if err is not None:
            self.report_case(test)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="List case numbers in a local checkout")
    args = parser.parse_args()
    sys.path.insert(0, str(Path.cwd()))
    suite = unittest.defaultTestLoader.discover("tests", pattern="test_*.py")
    cases = list(enumerate(test_cases(suite), start=1))
    numbers = {id(case): number for number, case in cases}
    if args.list:
        for number, case in cases:
            print(f"{number} {case.id()}")
        return int(bool(unittest.defaultTestLoader.errors))

    def result_factory(stream, descriptions, verbosity):
        return CaseNumberResult(stream, descriptions, verbosity, case_numbers=numbers)

    runner = unittest.TextTestRunner(verbosity=2, resultclass=result_factory)
    result = runner.run(suite)
    for number in sorted(result.failed_cases):
        print(f"CI_PYTHON_CASE_FAILED {number}")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
