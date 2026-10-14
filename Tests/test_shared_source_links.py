"""Ensure CLI tests compile production sources instead of drifting copies."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
sources = root / "Tools/IIJFetcher/Sources/IIJFetcher"
links = [path for path in sources.glob("*.swift") if path.name != "IIJFetcher.swift"]
assert links, "The fetcher must include shared production sources"
for path in sorted(links):
    assert path.is_symlink(), f"{path.name}: use a relative symlink, not a source copy"
    assert not path.readlink().is_absolute(), f"{path.name}: source link must be relative"
    target = path.resolve(strict=True)
    assert target.is_relative_to(root / "Shared") or target.is_relative_to(root / "IIJWidget"), (
        f"{path.name}: source link must stay inside this repository"
    )

print(f"Verified {len(links)} shared production source links")
