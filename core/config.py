import os
from dataclasses import dataclass
from pathlib import Path

from core.grid_map import dedupe_target_grids, load_district_grid_mappings, parse_district_names


@dataclass
class Settings:
    project_root: Path = Path(__file__).resolve().parent.parent
    kma_service_key: str = os.getenv("KMA_SERVICE_KEY", "")
    kma_base_url: str = os.getenv(
        "KMA_BASE_URL",
        "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0"
    )

    db_host: str = os.getenv("DB_HOST", "localhost")
    db_port: int = int(os.getenv("DB_PORT", "5432"))
    db_name: str = os.getenv("DB_NAME", "weather")
    db_user: str = os.getenv("DB_USER", "postgres")
    db_password: str = os.getenv("DB_PASSWORD", "postgres")

    seoul_api_base_url: str = os.getenv("SEOUL_API_BASE_URL", "http://openapi.seoul.go.kr:8088")
    seoul_rainfall_api_key: str = os.getenv("SEOUL_RAINFALL_API_KEY", "")
    seoul_river_api_key: str = os.getenv("SEOUL_RIVER_API_KEY", "")
    seoul_api_page_size: int = int(os.getenv("SEOUL_API_PAGE_SIZE", "200"))

    hsr_api_auth_key: str = os.getenv("HSR_API_AUTH_KEY", "")
    hsr_file_list_url: str = os.getenv(
        "HSR_FILE_LIST_URL",
        "https://apihub.kma.go.kr/api/typ01/url/rdr_cmp_file_list.php",
    )
    hsr_area_url: str = os.getenv(
        "HSR_AREA_URL",
        "https://apihub.kma.go.kr/api/typ02/openApi/WthrRadarInfoService/getCompCappiQcdArea",
    )
    hsr_lag_minutes: int = int(os.getenv("HSR_LAG_MINUTES", "10"))
    hsr_area_comp_type: str = os.getenv("HSR_AREA_COMP_TYPE", "CPP")
    hsr_area_data_type_cd: str = os.getenv("HSR_AREA_DATA_TYPE_CD", "CZ")
    hsr_area_lookback_steps: int = int(os.getenv("HSR_AREA_LOOKBACK_STEPS", "24"))

    request_connect_timeout_sec: int = int(os.getenv("REQUEST_CONNECT_TIMEOUT_SEC", "5"))
    request_read_timeout_sec: int = int(os.getenv("REQUEST_READ_TIMEOUT_SEC", "15"))
    page_size: int = int(os.getenv("KMA_PAGE_SIZE", "1000"))
    request_retry_count: int = int(os.getenv("KMA_REQUEST_RETRY_COUNT", "2"))
    request_retry_backoff_sec: float = float(os.getenv("KMA_REQUEST_RETRY_BACKOFF_SEC", "1.5"))
    db_batch_size: int = int(os.getenv("DB_BATCH_SIZE", "500"))

    ultra_now_lag_minutes: int = int(os.getenv("ULTRA_NOW_LAG_MINUTES", "10"))
    ultra_fcst_lag_minutes: int = int(os.getenv("ULTRA_FCST_LAG_MINUTES", "10"))
    short_fcst_lag_minutes: int = int(os.getenv("SHORT_FCST_LAG_MINUTES", "10"))
    district_grid_mapping_path: str = os.getenv(
        "DISTRICT_GRID_MAPPING_PATH",
        str(Path(__file__).resolve().parent.parent / "data" / "seoul_district_grids.csv"),
    )
    district_names_raw: str = os.getenv("DISTRICT_NAMES", "")

    # 서울 + 주변 격자 예시
    # 실제로는 별도 테이블/파일에서 관리하는 걸 추천
    target_grids: list[tuple[int, int]] = None

    def __post_init__(self) -> None:
        if self.target_grids is None:
            self.target_grids = [
                (60, 127),  # 서울 일부 예시
                (61, 127),
                (60, 126),
                (61, 126),
            ]

        district_names = parse_district_names(self.district_names_raw)
        mapped_grids = dedupe_target_grids(
            load_district_grid_mappings(
                self.district_grid_mapping_path,
                district_names=district_names or None,
            )
        )
        if mapped_grids:
            self.target_grids = mapped_grids


settings = Settings()