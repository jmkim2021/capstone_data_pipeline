-- 구별 대표 행정동·KMA 격자 (data/seoul_district_grids.csv)와 DB meta 동기화
-- 기존 (district_name, nx, ny) 조합이 바뀌므로 해당 구 행을 삭제 후 재삽입한다.
BEGIN;

DELETE FROM meta.seoul_district_grid_map
WHERE district_name IN (
    '강남구', '강동구', '강북구', '강서구', '관악구', '광진구', '구로구', '금천구',
    '노원구', '도봉구', '동대문구', '동작구', '마포구', '서대문구', '서초구',
    '성동구', '성북구', '송파구', '양천구', '영등포구', '용산구', '은평구',
    '종로구', '중구', '중랑구'
);

INSERT INTO meta.seoul_district_grid_map (district_name, nx, ny, weight, source) VALUES
('강남구', 61, 126, 1.0, 'representative_dong_kma_grid_v1'),
('강동구', 62, 126, 1.0, 'representative_dong_kma_grid_v1'),
('강북구', 61, 128, 1.0, 'representative_dong_kma_grid_v1'),
('강서구', 58, 126, 1.0, 'representative_dong_kma_grid_v1'),
('관악구', 59, 125, 1.0, 'representative_dong_kma_grid_v1'),
('광진구', 61, 126, 1.0, 'representative_dong_kma_grid_v1'),
('구로구', 58, 125, 1.0, 'representative_dong_kma_grid_v1'),
('금천구', 58, 124, 1.0, 'representative_dong_kma_grid_v1'),
('노원구', 61, 129, 1.0, 'representative_dong_kma_grid_v1'),
('도봉구', 61, 129, 1.0, 'representative_dong_kma_grid_v1'),
('동대문구', 61, 127, 1.0, 'representative_dong_kma_grid_v1'),
('동작구', 59, 125, 1.0, 'representative_dong_kma_grid_v1'),
('마포구', 59, 127, 1.0, 'representative_dong_kma_grid_v1'),
('서대문구', 59, 127, 1.0, 'representative_dong_kma_grid_v1'),
('서초구', 61, 125, 1.0, 'representative_dong_kma_grid_v1'),
('성동구', 61, 127, 1.0, 'representative_dong_kma_grid_v1'),
('성북구', 60, 127, 1.0, 'representative_dong_kma_grid_v1'),
('송파구', 62, 126, 1.0, 'representative_dong_kma_grid_v1'),
('양천구', 58, 126, 1.0, 'representative_dong_kma_grid_v1'),
('영등포구', 59, 126, 1.0, 'representative_dong_kma_grid_v1'),
('용산구', 60, 126, 1.0, 'representative_dong_kma_grid_v1'),
('은평구', 59, 128, 1.0, 'representative_dong_kma_grid_v1'),
('종로구', 60, 127, 1.0, 'representative_dong_kma_grid_v1'),
('중구', 60, 127, 1.0, 'representative_dong_kma_grid_v1'),
('중랑구', 62, 128, 1.0, 'representative_dong_kma_grid_v1');

COMMIT;
