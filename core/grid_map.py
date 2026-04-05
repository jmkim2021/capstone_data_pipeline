from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class DistrictGridMapping:
    district_name: str
    nx: int
    ny: int
    weight: float = 1.0


def parse_district_names(raw_value: str) -> list[str]:
    return [name.strip() for name in raw_value.split(",") if name.strip()]


def load_district_grid_mappings(
    mapping_path: str,
    district_names: list[str] | None = None,
) -> list[DistrictGridMapping]:
    if not mapping_path:
        return []

    path = Path(mapping_path)
    if not path.exists():
        return []

    requested_districts = set(district_names or [])
    mappings: list[DistrictGridMapping] = []

    with path.open("r", encoding="utf-8-sig", newline="") as fp:
        reader = csv.DictReader(fp)
        required_fields = {"district_name", "nx", "ny"}
        if reader.fieldnames is None or not required_fields.issubset(reader.fieldnames):
            raise ValueError(
                "district grid mapping file must include district_name, nx, ny columns"
            )

        for row in reader:
            district_name = (row.get("district_name") or "").strip()
            if not district_name:
                continue
            if requested_districts and district_name not in requested_districts:
                continue

            weight_raw = (row.get("weight") or "").strip()
            weight = float(weight_raw) if weight_raw else 1.0
            mappings.append(
                DistrictGridMapping(
                    district_name=district_name,
                    nx=int(row["nx"]),
                    ny=int(row["ny"]),
                    weight=weight,
                )
            )

    return mappings


def dedupe_target_grids(mappings: list[DistrictGridMapping]) -> list[tuple[int, int]]:
    seen: set[tuple[int, int]] = set()
    grids: list[tuple[int, int]] = []

    for mapping in mappings:
        grid = (mapping.nx, mapping.ny)
        if grid in seen:
            continue
        seen.add(grid)
        grids.append(grid)

    return grids
