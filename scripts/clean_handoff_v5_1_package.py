#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
import shutil
import zipfile
from pathlib import Path
from typing import Iterable


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE_HANDOFF = PROJECT_ROOT / "handoff_v5_1"
STAGING_DIR = PROJECT_ROOT / "handoff_v5_1_clean"
FINAL_HANDOFF = PROJECT_ROOT / "handoff_v5_1"
ZIP_OUT = PROJECT_ROOT / "handoff_v5_1_final.zip"

ABS_PATH_PATTERN = re.compile(r"/Users/[^\s'\"]+|/home/[^\s'\"]+")

JUNK_NAMES = {".DS_Store", ".localized"}
JUNK_DIR_NAMES = {"__MACOSX"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sanitize handoff_v5_1: remove absolute paths from manifests, "
        "harden README files, strip junk files, optionally replace handoff_v5_1 and build zip."
    )
    parser.add_argument(
        "--staging-only",
        action="store_true",
        help="Write only to handoff_v5_1_clean and zip; do not replace handoff_v5_1.",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=SOURCE_HANDOFF,
        help="Source handoff directory to copy from (default: project handoff_v5_1).",
    )
    return parser.parse_args()


def remove_junk_under(root: Path) -> list[str]:
    removed: list[str] = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.name in JUNK_NAMES:
            path.unlink()
            removed.append(str(path.relative_to(root)))
    for path in sorted(root.rglob("__MACOSX"), reverse=True):
        if path.is_dir():
            shutil.rmtree(path)
            removed.append(str(path.relative_to(root)))
    return removed


def scan_for_absolute_paths(root: Path) -> list[tuple[str, int, str]]:
    hits: list[tuple[str, int, str]] = []
    text_suffixes = {".txt", ".csv", ".sql", ".py", ".md", ".env"}
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in text_suffixes and path.name not in {
            "README_FOR_MODELING.txt",
            "README_FOR_ANALYSIS.txt",
        }:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for i, line in enumerate(text.splitlines(), start=1):
            if ABS_PATH_PATTERN.search(line) or "Desktop/project" in line:
                hits.append((str(path.relative_to(root)), i, line.strip()[:200]))
    return hits


def manifest_rows() -> list[dict[str, str]]:
    return [
        {
            "handoff_relative_path": "data/train_features_only.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_train_features_only_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "DB export snapshot bundled under handoff data/ with stable short name.",
        },
        {
            "handoff_relative_path": "data/valid_features_only.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_valid_features_only_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Supplementary; not the primary training matrix. Prefer model_input for training.",
        },
        {
            "handoff_relative_path": "data/test_features_only.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_test_features_only_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Supplementary; not the primary training matrix.",
        },
        {
            "handoff_relative_path": "data/inference_features_latest.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_inference_features_latest_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Latest-hour feature-only snapshot; schema matches train feature-only.",
        },
        {
            "handoff_relative_path": "data/train_labels.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_train_labels_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "modeling",
            "notes": "Join to model_input on district_name + base_datetime.",
        },
        {
            "handoff_relative_path": "data/valid_labels.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_valid_labels_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "modeling",
            "notes": "Join to model_input on district_name + base_datetime.",
        },
        {
            "handoff_relative_path": "data/test_labels.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_test_labels_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "modeling",
            "notes": "Join to model_input on district_name + base_datetime.",
        },
        {
            "handoff_relative_path": "data/train_audit.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_train_audit_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "analysis",
            "notes": "Full provenance and label components; primary for analysts.",
        },
        {
            "handoff_relative_path": "data/valid_audit.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_valid_audit_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "analysis",
            "notes": "Full provenance and label components.",
        },
        {
            "handoff_relative_path": "data/test_audit.csv",
            "role": "existing_export_asset",
            "original_artifact_name": "seoul_test_audit_v5_1_aws_20260402.csv",
            "source_type": "upstream_export",
            "generation_method": "copy",
            "consumer_role": "analysis",
            "notes": "Full provenance and label components.",
        },
        {
            "handoff_relative_path": "reference/README.md",
            "role": "reference_document",
            "original_artifact_name": "README.md",
            "source_type": "repository_reference",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Project-wide context; not rewritten for this handoff.",
        },
        {
            "handoff_relative_path": "reference/MODELING_HANDOFF.md",
            "role": "reference_document",
            "original_artifact_name": "MODELING_HANDOFF.md",
            "source_type": "repository_reference",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Legacy handoff notes; prefer metadata/*.txt in this package for v5.1 contract.",
        },
        {
            "handoff_relative_path": "sql/021_heavyrain_modelready_aws_v5_1_final.sql",
            "role": "reference_sql",
            "original_artifact_name": "021_heavyrain_modelready_aws_v5_1_final.sql",
            "source_type": "repository_reference",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Canonical dataset definition in SQL form.",
        },
        {
            "handoff_relative_path": "sql/021_heavyrain_modelready_aws_v5_1_validation_gates.sql",
            "role": "reference_sql",
            "original_artifact_name": "021_heavyrain_modelready_aws_v5_1_validation_gates.sql",
            "source_type": "repository_reference",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Validation gate queries for DB replay.",
        },
        {
            "handoff_relative_path": "sql/021_heavyrain_modelready_aws_v5_1_diagnostics.sql",
            "role": "reference_sql",
            "original_artifact_name": "021_heavyrain_modelready_aws_v5_1_diagnostics.sql",
            "source_type": "repository_reference",
            "generation_method": "copy",
            "consumer_role": "both",
            "notes": "Diagnostic queries for DB replay.",
        },
        {
            "handoff_relative_path": "scripts/export_seoul_district_heavyrain_modelready_v5_1_aws.py",
            "role": "reference_export_script",
            "original_artifact_name": "export_seoul_district_heavyrain_modelready_v5_1_aws.py",
            "source_type": "repository_reference",
            "generation_method": "copy",
            "consumer_role": "reexport",
            "notes": "Requires DB credentials; not needed for CSV-only modeling.",
        },
        {
            "handoff_relative_path": "scripts/build_handoff_v5_1_package.py",
            "role": "reference_build_script",
            "original_artifact_name": "build_handoff_v5_1_package.py",
            "source_type": "repository_reference",
            "generation_method": "copy",
            "consumer_role": "reexport",
            "notes": "Rebuilds handoff from repo trainset exports.",
        },
        {
            "handoff_relative_path": "data/train_model_input.csv",
            "role": "generated_model_input",
            "original_artifact_name": "seoul_train_features_only_v5_1_aws_20260402.csv",
            "source_type": "package_derived",
            "generation_method": "generated_from_feature_only_csv",
            "consumer_role": "modeling",
            "notes": "Primary training features: adds district_id and calendar encodings. Use with train_labels.csv.",
        },
        {
            "handoff_relative_path": "data/valid_model_input.csv",
            "role": "generated_model_input",
            "original_artifact_name": "seoul_valid_features_only_v5_1_aws_20260402.csv",
            "source_type": "package_derived",
            "generation_method": "generated_from_feature_only_csv",
            "consumer_role": "modeling",
            "notes": "Primary validation features. Use with valid_labels.csv.",
        },
        {
            "handoff_relative_path": "data/test_model_input.csv",
            "role": "generated_model_input",
            "original_artifact_name": "seoul_test_features_only_v5_1_aws_20260402.csv",
            "source_type": "package_derived",
            "generation_method": "generated_from_feature_only_csv",
            "consumer_role": "modeling",
            "notes": "Primary test features. Use with test_labels.csv.",
        },
        {
            "handoff_relative_path": "data/inference_model_input_latest.csv",
            "role": "generated_model_input",
            "original_artifact_name": "seoul_inference_features_latest_v5_1_aws_20260402.csv",
            "source_type": "package_derived",
            "generation_method": "generated_from_feature_only_csv",
            "consumer_role": "modeling",
            "notes": "Serve-time input shape aligned with train model_input column order.",
        },
        {
            "handoff_relative_path": "metadata/district_index.csv",
            "role": "district_mapping",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Stable district_id mapping for 24 districts.",
        },
        {
            "handoff_relative_path": "metadata/feature_dictionary.csv",
            "role": "model_input_dictionary",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "modeling",
            "notes": "Column semantics for model_input.",
        },
        {
            "handoff_relative_path": "metadata/audit_dictionary.csv",
            "role": "audit_dictionary",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "analysis",
            "notes": "Column semantics for audit CSV.",
        },
        {
            "handoff_relative_path": "metadata/class_balance_summary.csv",
            "role": "class_imbalance_summary",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "modeling",
            "notes": "Positive rates by split.",
        },
        {
            "handoff_relative_path": "metadata/split_summary.csv",
            "role": "split_summary",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Row counts and drop rates.",
        },
        {
            "handoff_relative_path": "metadata/drop_reason_summary.csv",
            "role": "drop_reason_summary",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "analysis",
            "notes": "Null-field counts for dropped rows.",
        },
        {
            "handoff_relative_path": "metadata/feature_label_join_map.csv",
            "role": "join_contract",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Which files join on which keys.",
        },
        {
            "handoff_relative_path": "README_FOR_MODELING.txt",
            "role": "primary_modeling_readme",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "modeling",
            "notes": "Start here for modeling.",
        },
        {
            "handoff_relative_path": "README_FOR_ANALYSIS.txt",
            "role": "primary_analysis_readme",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "analysis",
            "notes": "Start here for analysis and provenance.",
        },
        {
            "handoff_relative_path": "metadata/label_policy.txt",
            "role": "label_policy_document",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Label rule text for v5.1.",
        },
        {
            "handoff_relative_path": "metadata/split_policy.txt",
            "role": "split_policy_document",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Time windows for train/valid/test.",
        },
        {
            "handoff_relative_path": "metadata/district_universe.txt",
            "role": "district_universe_document",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "24 districts, 종로구 excluded.",
        },
        {
            "handoff_relative_path": "metadata/preprocessing_spec.txt",
            "role": "preprocessing_spec_document",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Imputation and feature rules.",
        },
        {
            "handoff_relative_path": "metadata/validation_summary.txt",
            "role": "validation_summary_document",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Gate-style summary from packaged CSV checks.",
        },
        {
            "handoff_relative_path": "sql/export_model_input.sql",
            "role": "reexport_sql",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "reexport",
            "notes": "psql \\copy templates; paths relative to handoff root. Run psql with cwd = this package root.",
        },
        {
            "handoff_relative_path": "sql/export_audit.sql",
            "role": "reexport_sql",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "reexport",
            "notes": "psql \\copy templates; paths relative to handoff root.",
        },
        {
            "handoff_relative_path": "metadata/source_file_mapping.csv",
            "role": "source_mapping",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "No local absolute paths; use handoff_relative_path as the locator inside the package.",
        },
        {
            "handoff_relative_path": "FILE_MANIFEST.txt",
            "role": "package_inventory",
            "original_artifact_name": "N/A",
            "source_type": "package_generated",
            "generation_method": "newly_generated",
            "consumer_role": "both",
            "notes": "Human-readable inventory; no machine-local paths.",
        },
    ]


def write_file_manifest(root: Path, rows: Iterable[dict[str, str]]) -> None:
    lines = [
        "FILE_MANIFEST",
        "",
        "This manifest uses only paths and names that exist inside the handoff package.",
        "No local machine absolute paths are stored here.",
        "",
        "Per entry:",
        "- package_relative_path",
        "- role",
        "- original_artifact_name",
        "- generation_method",
        "- consumer_role",
        "- notes",
        "",
    ]
    for row in rows:
        lines.append(f"package_relative_path: {row['handoff_relative_path']}")
        lines.append(f"role: {row['role']}")
        lines.append(f"original_artifact_name: {row['original_artifact_name']}")
        lines.append(f"generation_method: {row['generation_method']}")
        lines.append(f"consumer_role: {row['consumer_role']}")
        lines.append(f"notes: {row['notes']}")
        lines.append("")
    (root / "FILE_MANIFEST.txt").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def write_source_file_mapping_csv(root: Path, rows: Iterable[dict[str, str]]) -> None:
    path = root / "metadata" / "source_file_mapping.csv"
    fieldnames = [
        "handoff_relative_path",
        "original_artifact_name",
        "source_type",
        "generation_method",
        "consumer_role",
        "notes",
    ]
    with path.open("w", encoding="utf-8", newline="") as fp:
        writer = csv.DictWriter(fp, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "handoff_relative_path": row["handoff_relative_path"],
                    "original_artifact_name": row["original_artifact_name"],
                    "source_type": row["source_type"],
                    "generation_method": row["generation_method"],
                    "consumer_role": row["consumer_role"],
                    "notes": row["notes"],
                }
            )


def write_readme_modeling(root: Path) -> None:
    text = """v5.1 모델링 handoff 패키지 안내

================================================================================
필수 계약 (이 문단을 먼저 읽으십시오)
================================================================================

학습과 검증, 테스트는 반드시 아래 조합으로 진행하십시오.

- 학습 입력: data/train_model_input.csv
- 학습 라벨: data/train_labels.csv
- 검증 입력: data/valid_model_input.csv
- 검증 라벨: data/valid_labels.csv
- 테스트 입력: data/test_model_input.csv
- 테스트 라벨: data/test_labels.csv

data/*_features_only.csv 파일은 보조 참고용입니다.
feature-only CSV만 가지고 단독으로 학습 파이프라인을 구성하는 것은 권장하지 않습니다.
이유는 district_id, base_hour, base_month, day_of_week, hour_sin, hour_cos, month_sin, month_cos, is_monsoon_season_flag 가 빠져 있어 train/serve 전처리를 수신 측이 다시 구현해야 하고 불일치 위험이 커지기 때문입니다.

조인 키는 district_name 과 base_datetime 입니다.
district_name 과 base_datetime 은 행 식별과 조인용이며, 수치 모델의 raw 입력으로 그대로 넣는 것은 권장하지 않습니다.
수치 특성은 metadata/feature_dictionary.csv 의 권장 컬럼을 따르십시오.

최종 라벨 정책은 1시간 누적 20mm 이상 또는 3시간 누적 40mm 이상을 lead 0에서 3시간까지 확장한 규칙입니다.
자세한 서술은 metadata/label_policy.txt 를 보십시오.

추론 입력은 data/inference_model_input_latest.csv 를 사용하십시오.
컬럼 순서와 의미는 학습용 model_input 과 동일하게 맞춰져 있습니다.

================================================================================
가장 먼저 볼 파일 (순서)
================================================================================

1. README_FOR_MODELING.txt (현재 파일)
2. data/train_model_input.csv
3. data/train_labels.csv
4. metadata/feature_dictionary.csv
5. metadata/label_policy.txt
6. metadata/split_policy.txt
7. metadata/district_index.csv
8. data/inference_model_input_latest.csv

================================================================================
바로 학습할 때 쓰는 파일 (요약)
================================================================================

- 학습 입력: data/train_model_input.csv
- 검증 입력: data/valid_model_input.csv
- 테스트 입력: data/test_model_input.csv
- 학습 라벨: data/train_labels.csv
- 검증 라벨: data/valid_labels.csv
- 테스트 라벨: data/test_labels.csv
- 최신 추론 입력: data/inference_model_input_latest.csv

================================================================================
조인 키
================================================================================

- district_name
- base_datetime

================================================================================
feature-only 와 model_input 의 역할 구분
================================================================================

- model_input: 학습과 서빙에 쓰는 최종 계약본입니다. district_id 와 시간 파생 특성이 포함됩니다.
- feature-only: 동일 시점의 축약된 기상 특성만 담습니다. 스키마 점검이나 단순 EDA 보조용으로 두었습니다.
- 단독으로 feature-only 만 넘겨받은 것처럼 학습하면 안 됩니다. 반드시 이 패키지의 model_input + labels 조합을 사용하십시오.

================================================================================
권장 수치 입력 컬럼 (X 행렬)
================================================================================

- district_id
- base_hour
- base_month
- day_of_week
- is_monsoon_season_flag
- hour_sin
- hour_cos
- month_sin
- month_cos
- temp_c
- precip_mm
- humidity_pct
- dew_point_c
- past_rain_3h_mm
- temp_change_3h_c
- humidity_change_3h_pct
- moist_energy

================================================================================
권장 제외 또는 별도 처리
================================================================================

- district_name
- base_datetime

================================================================================
클래스 불균형 요약
================================================================================

- train: 3216 positive / 834617 rows (0.003853)
- valid: 537 positive / 209442 rows (0.002564)
- test: 723 positive / 209319 rows (0.003454)

================================================================================
stable district universe
================================================================================

- 총 24개 구
- 종로구 제외
- 순서: 강남구, 강동구, 강북구, 강서구, 관악구, 광진구, 구로구, 금천구, 노원구, 도봉구, 동대문구, 동작구, 마포구, 서대문구, 서초구, 성동구, 성북구, 송파구, 양천구, 영등포구, 용산구, 은평구, 중구, 중랑구

================================================================================
주의사항
================================================================================

- 현재 패키지 기준 라벨 원천은 audit CSV 와 final SQL 에 기록된 std.seoul_aws_district_hourly 입니다.
- 기존 상위 문서 중 일부에는 서울시 강우량 기반이라고 적힌 구간이 있으나, 이 패키지에서는 실제 export 결과를 source of truth 로 사용합니다.
- leakage 방지를 위해 target_rain_1h_mm, target_rain_3h_mm, label 컬럼은 model_input CSV 에 포함하지 않았습니다.

================================================================================
참고 파일
================================================================================

- data/train_features_only.csv, data/valid_features_only.csv, data/test_features_only.csv
- data/inference_features_latest.csv
- data/train_audit.csv, data/valid_audit.csv, data/test_audit.csv
- metadata/class_balance_summary.csv
- metadata/validation_summary.txt
- metadata/source_file_mapping.csv
- FILE_MANIFEST.txt
"""
    (root / "README_FOR_MODELING.txt").write_text(text, encoding="utf-8")


def write_readme_analysis(root: Path) -> None:
    text = """v5.1 분석 handoff 패키지 안내

================================================================================
필수 계약 (이 문단을 먼저 읽으십시오)
================================================================================

분석, EDA, 라벨 검증, 전처리 추적, 행 드롭 원인 분석의 1차 소스는 audit CSV 입니다.

- data/train_audit.csv
- data/valid_audit.csv
- data/test_audit.csv

위 세 파일은 동일 스키마이며 split 만 다릅니다.

feature-only CSV 는 모델 입력용으로 축약된 결과물입니다.
provenance, raw 대비 effective 값, 결측 플래그, 라벨 구성 요소를 보려면 audit 을 사용하십시오.

validation 요약과 집계는 metadata/validation_summary.txt 와 metadata/split_summary.csv, metadata/drop_reason_summary.csv 에 있습니다.
컬럼 의미는 metadata/audit_dictionary.csv 에 정리되어 있습니다.

================================================================================
가장 먼저 볼 파일 (순서)
================================================================================

1. README_FOR_ANALYSIS.txt (현재 파일)
2. data/train_audit.csv
3. metadata/audit_dictionary.csv
4. metadata/label_policy.txt
5. metadata/preprocessing_spec.txt
6. metadata/split_policy.txt
7. metadata/validation_summary.txt
8. metadata/drop_reason_summary.csv

================================================================================
분석 시작용 핵심 파일
================================================================================

- 전체 provenance/품질 추적: data/train_audit.csv, data/valid_audit.csv, data/test_audit.csv
- 전처리 규칙 사전: metadata/audit_dictionary.csv
- 라벨 규칙: metadata/label_policy.txt
- split 범위: metadata/split_policy.txt
- district universe: metadata/district_universe.txt
- validation 결과 요약: metadata/validation_summary.txt
- 행 수와 드롭률 요약: metadata/split_summary.csv
- 드롭 원인 null 카운트: metadata/drop_reason_summary.csv
- 패키지 내 파일 출처 표: metadata/source_file_mapping.csv

================================================================================
audit CSV 에서 바로 확인 가능한 항목 (provenance)
================================================================================

- observed/raw 값: precip_mm_observed, humidity_pct_observed
- effective/imputed 값: precip_mm_eff, humidity_imputed_pct, humidity_locf_raw
- missing/default 플래그: precip_raw_was_null, humidity_raw_was_null, humidity_used_default_prior
- 라벨 provenance: label_source_point_count, target_rain_1h_mm, target_rain_3h_mm, label_source_name, label_rule_name
- 전처리 provenance: preprocessing_rule_name, data_version
- model_input 적격 여부: is_model_input_ready

================================================================================
feature-only 의 역할 (분석 관점)
================================================================================

- 모델링 담당자에게 넘긴 최종 학습 행과 동일한 기상 특성만 담은 축약본입니다.
- 원시값, 보간 과정, 라벨 산출에 쓰인 중간값을 보려면 audit 이 필요합니다.
- train 행 드롭 원인은 audit 의 is_model_input_ready 와 null 컬럼을 이용해 설명할 수 있습니다.

================================================================================
drop 요약
================================================================================

- train: audit 837747 rows, ready 834617, dropped 3130 (0.003736)
- valid: audit 209911 rows, ready 209442, dropped 469 (0.002234)
- test: audit 209941 rows, ready 209319, dropped 622 (0.002963)

================================================================================
stable district universe
================================================================================

- 총 24개 구
- 종로구 제외
- 순서: 강남구, 강동구, 강북구, 강서구, 관악구, 광진구, 구로구, 금천구, 노원구, 도봉구, 동대문구, 동작구, 마포구, 서대문구, 서초구, 성동구, 성북구, 송파구, 양천구, 영등포구, 용산구, 은평구, 중구, 중랑구

================================================================================
중요 해석 포인트
================================================================================

- label_rule_name, preprocessing_rule_name, data_version 이 모든 split 에서 고정값인지 반드시 확인해야 합니다.
- 현재 패키지 기준 라벨 원천은 std.seoul_aws_district_hourly 로 기록되어 있습니다.

================================================================================
추가 참고
================================================================================

- sql/021_heavyrain_modelready_aws_v5_1_final.sql
- sql/021_heavyrain_modelready_aws_v5_1_validation_gates.sql
- sql/021_heavyrain_modelready_aws_v5_1_diagnostics.sql
- sql/export_audit.sql
- sql/export_model_input.sql
- reference/README.md
- reference/MODELING_HANDOFF.md
- FILE_MANIFEST.txt
"""
    (root / "README_FOR_ANALYSIS.txt").write_text(text, encoding="utf-8")


def write_export_sql_relative(root: Path) -> None:
    model_input = """-- Run psql from the handoff package root directory so relative paths resolve.
-- Example: cd /path/to/handoff_v5_1 && psql ... -f sql/export_model_input.sql

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_train_model_input_20260402
ORDER BY district_name, base_datetime
) TO 'data/train_model_input.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_valid_model_input_20260402
ORDER BY district_name, base_datetime
) TO 'data/valid_model_input.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_test_model_input_20260402
ORDER BY district_name, base_datetime
) TO 'data/test_model_input.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_inference_model_input_latest_20260402
ORDER BY district_name, base_datetime
) TO 'data/inference_model_input_latest.csv' CSV HEADER;
"""
    audit_sql = """-- Run psql from the handoff package root directory so relative paths resolve.

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_train_audit_20260402
ORDER BY district_name, base_datetime
) TO 'data/train_audit.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_valid_audit_20260402
ORDER BY district_name, base_datetime
) TO 'data/valid_audit.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_test_audit_20260402
ORDER BY district_name, base_datetime
) TO 'data/test_audit.csv' CSV HEADER;
"""
    (root / "sql" / "export_model_input.sql").write_text(model_input, encoding="utf-8")
    (root / "sql" / "export_audit.sql").write_text(audit_sql, encoding="utf-8")


def zip_handoff(handoff_dir: Path, zip_path: Path, arc_root_name: str) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(handoff_dir.rglob("*")):
            if path.is_dir():
                continue
            if path.name in JUNK_NAMES:
                continue
            if "__MACOSX" in path.parts:
                continue
            rel = path.relative_to(handoff_dir)
            arcname = Path(arc_root_name) / rel
            zf.write(path, arcname)


def main() -> None:
    args = parse_args()
    source = args.source_dir.resolve()
    if not source.is_dir():
        raise FileNotFoundError(f"Source handoff directory not found: {source}")

    pre_scan = scan_for_absolute_paths(source)
    print("=== Pre-clean absolute-path scan (source tree) ===")
    for path, line_no, line in pre_scan:
        print(f"{path}:{line_no}: {line}")
    if not pre_scan:
        print("(no absolute paths detected in scanned text files)")

    if STAGING_DIR.exists():
        shutil.rmtree(STAGING_DIR)

    def ignore_copy(dir_path: str, names: list[str]) -> list[str]:
        ignored: list[str] = []
        for name in names:
            if name in JUNK_DIR_NAMES or name in JUNK_NAMES:
                ignored.append(name)
        return ignored

    shutil.copytree(source, STAGING_DIR, ignore=ignore_copy)
    junk_removed = remove_junk_under(STAGING_DIR)
    rows = list(manifest_rows())
    write_file_manifest(STAGING_DIR, rows)
    write_source_file_mapping_csv(STAGING_DIR, rows)
    write_readme_modeling(STAGING_DIR)
    write_readme_analysis(STAGING_DIR)
    write_export_sql_relative(STAGING_DIR)

    post_scan = scan_for_absolute_paths(STAGING_DIR)
    print("\n=== Post-clean absolute-path scan (staging tree) ===")
    for path, line_no, line in post_scan:
        print(f"{path}:{line_no}: {line}")
    if not post_scan:
        print("(no absolute paths detected)")

    print("\n=== Removed junk ===")
    for item in junk_removed:
        print(item)
    if not junk_removed:
        print("(none)")

    zip_handoff(STAGING_DIR, ZIP_OUT, "handoff_v5_1")
    print(f"\nWrote zip: {ZIP_OUT}")

    if args.staging_only:
        print(f"\nStaging only: clean tree left at {STAGING_DIR}")
        print("handoff_v5_1 was not modified.")
        return

    if FINAL_HANDOFF.resolve() == STAGING_DIR.resolve():
        raise RuntimeError("FINAL_HANDOFF and STAGING_DIR must differ")

    if FINAL_HANDOFF.exists():
        shutil.rmtree(FINAL_HANDOFF)
    shutil.move(str(STAGING_DIR), str(FINAL_HANDOFF))
    print(f"\nReplaced {FINAL_HANDOFF} with cleaned content.")

    zip_handoff(FINAL_HANDOFF, ZIP_OUT, "handoff_v5_1")
    print(f"Refreshed zip: {ZIP_OUT}")


if __name__ == "__main__":
    main()
