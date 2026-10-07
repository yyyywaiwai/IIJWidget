"""Run with: python3 Tests/test_usage_chart_lifecycle.py"""

from pathlib import Path
import re


source = (
    Path(__file__).resolve().parents[1]
    / "IIJWidget/Views/Components/Charts/UsageChartCards.swift"
).read_text()

for name in ("MonthlyUsageChartCard", "DailyUsageChartCard"):
    card = source.split(f"struct {name}: View {{", 1)[1].split("\nstruct ", 1)[0]
    on_appear = re.search(r"\.onAppear\s*\{([^{}]*)\}", card)
    assert on_appear and "triggerBarAnimation()" in on_appear[1], (
        f"{name}: reappearing with unchanged cached data must restart the bars"
    )

print("Monthly and daily chart appearance checks passed")
