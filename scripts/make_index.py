"""Build public/index.html from the site template + latest test results."""

from datetime import datetime, timezone
from pathlib import Path

from robot.api import ExecutionResult

RESULTS = Path("results/output.xml")
TEMPLATE = Path("site/index.html")
OUT = Path("public/index.html")


def main() -> None:
    result = ExecutionResult(RESULTS)
    stats = result.statistics.total
    passed, failed = stats.passed, stats.failed
    total = passed + failed + stats.skipped

    html = TEMPLATE.read_text(encoding="utf-8")
    html = (
        html.replace("{{PASSED}}", str(passed))
        .replace("{{TOTAL}}", str(total))
        .replace("{{STATUS_CLASS}}", "pass" if failed ==  0 else "fail")
        .replace("{{TIMESTAMP}}", datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M"))
    )
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(html, encoding="utf-8")
    print(f"iindex.html written: {passed}/{total} passed")


if __name__ == "__main__":
    main()
                 