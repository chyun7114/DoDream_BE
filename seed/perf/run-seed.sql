/*
  DoDream performance seed script
  - Scale selection: S / M / L
  - Default: S
  - Usage (docker mysql):
      SET @seed_scale = 'M';
      SOURCE run-seed.sql;

  NOTE:
  - This script resets performance-domain data by TRUNCATE.
  - It keeps `region` as-is (creates one fallback row only when empty).
*/

SET @seed_scale = COALESCE(@seed_scale, 'S');
SET @seed_scale = UPPER(@seed_scale);

DROP PROCEDURE IF EXISTS sp_seed_perf;

DELIMITER $$
CREATE PROCEDURE sp_seed_perf(IN p_scale VARCHAR(1))
BEGIN
    DECLARE v_scale VARCHAR(1);
    DECLARE v_member_target INT;
    DECLARE v_job_target INT;
    DECLARE v_group_target INT;
    DECLARE v_recruit_scrap_target INT;
    DECLARE v_training_scrap_target INT;

    DECLARE v_heavy_member_target INT;
    DECLARE v_heavy_group_target INT;

    DECLARE v_need_seq INT;
    DECLARE v_max_seq INT;

    DECLARE v_region_id BIGINT;
    DECLARE v_base_todo_count BIGINT;

    SET v_scale = UPPER(COALESCE(p_scale, 'S'));

    IF v_scale = 'S' THEN
        SET v_member_target = 5000;
        SET v_job_target = 1000;
        SET v_group_target = 7500;
        SET v_recruit_scrap_target = 80000;
        SET v_training_scrap_target = 50000;
    ELSEIF v_scale = 'M' THEN
        SET v_member_target = 20000;
        SET v_job_target = 5000;
        SET v_group_target = 30000;
        SET v_recruit_scrap_target = 300000;
        SET v_training_scrap_target = 180000;
    ELSEIF v_scale = 'L' THEN
        SET v_member_target = 50000;
        SET v_job_target = 10000;
        SET v_group_target = 75000;
        SET v_recruit_scrap_target = 900000;
        SET v_training_scrap_target = 500000;
    ELSE
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid scale. Use S / M / L';
    END IF;

    /*
      Additional distribution constraints from docs:
      - top 10% members: 300~1000 saved other todos
      - top 20 jobs concentration
      - top 5% groups: 80+ todos, others: 20~30
    */
    SET v_heavy_member_target = FLOOR(v_member_target * 0.10);
    SET v_heavy_group_target = FLOOR(v_group_target * 0.05);

    /* Sequence table upper bound:
       - saved todos: heavy members * up to 1000
       - scraps: up to 900k
       - safety margin for joins
    */
    SET v_need_seq = GREATEST(v_heavy_member_target * 1000, v_recruit_scrap_target, v_training_scrap_target, 2000000);

    CREATE TABLE IF NOT EXISTS perf_seed_seq (
        n INT NOT NULL PRIMARY KEY
    ) ENGINE=InnoDB;

    IF (SELECT COUNT(*) FROM perf_seed_seq) = 0 THEN
        INSERT INTO perf_seed_seq(n) VALUES (1);
    END IF;

    SET v_max_seq = (SELECT MAX(n) FROM perf_seed_seq);
    WHILE v_max_seq < v_need_seq DO
        INSERT IGNORE INTO perf_seed_seq(n)
        SELECT n + v_max_seq
        FROM perf_seed_seq
        WHERE n + v_max_seq <= v_need_seq;

        SET v_max_seq = (SELECT MAX(n) FROM perf_seed_seq);
    END WHILE;

    /* Keep table compact for repeated runs */
    DELETE FROM perf_seed_seq WHERE n > v_need_seq;

    /* Ensure region exists */
    IF (SELECT COUNT(*) FROM region) = 0 THEN
        INSERT INTO region (created_at, updated_at, deleted, region_code, region_name, saramin_region_code)
        VALUES (NOW(), NOW(), FALSE, 'R-000', 'Seed Region', '101000');
    END IF;
    SET v_region_id = (SELECT id FROM region ORDER BY id LIMIT 1);

    /* Reset workload tables (deterministic rerun) */
    SET FOREIGN_KEY_CHECKS = 0;
    TRUNCATE TABLE member_training_scrap;
    TRUNCATE TABLE member_recruit_scrap;
    TRUNCATE TABLE todo;
    TRUNCATE TABLE todo_group;
    TRUNCATE TABLE member;
    TRUNCATE TABLE certification;
    TRUNCATE TABLE job_todo;
    TRUNCATE TABLE job;
    SET FOREIGN_KEY_CHECKS = 1;

    /* Jobs */
    INSERT INTO job (
        created_at, updated_at, deleted,
        job_name, requires_certification, work_time_slot, salary_type, salary_cost,
        interpersonal_contact_level, physical_activity_level, emotional_labor_level,
        job_image_url, ncs_name, job_summary, todo_group_num
    )
    SELECT
        NOW(), NOW(), FALSE,
        CONCAT('SEED_JOB_', LPAD(s.n, 5, '0')),
        CASE MOD(s.n, 3)
            WHEN 0 THEN 'REQUIRED'
            WHEN 1 THEN 'OPTIONAL'
            ELSE 'NONE'
        END,
        CASE MOD(s.n, 6)
            WHEN 0 THEN 'WEEKDAY_MORNING'
            WHEN 1 THEN 'WEEKDAY_AFTERNOON'
            WHEN 2 THEN 'WEEKDAY_NINE_TO_SIX'
            WHEN 3 THEN 'WEEKEND'
            WHEN 4 THEN 'EVENT'
            ELSE 'FLEXIBLE'
        END,
        CASE MOD(s.n, 3)
            WHEN 0 THEN 'MONTHLY'
            WHEN 1 THEN 'DAILY'
            ELSE 'PER_CASE'
        END,
        180 + MOD(s.n * 17, 150),
        CASE MOD(s.n, 3)
            WHEN 0 THEN 'HIGH'
            WHEN 1 THEN 'MEDIUM'
            ELSE 'LOW'
        END,
        CASE MOD(s.n + 1, 3)
            WHEN 0 THEN 'HIGH'
            WHEN 1 THEN 'MEDIUM'
            ELSE 'LOW'
        END,
        CASE MOD(s.n + 2, 3)
            WHEN 0 THEN 'HIGH'
            WHEN 1 THEN 'MEDIUM'
            ELSE 'LOW'
        END,
        CONCAT('https://seed.local/job/', s.n),
        CONCAT('NCS-', LPAD(MOD(s.n, 99999), 5, '0')),
        CONCAT('Seed generated job summary #', s.n),
        0
    FROM perf_seed_seq s
    WHERE s.n <= v_job_target
    ORDER BY s.n;

    /* Members */
    INSERT INTO member (
        created_at, updated_at, deleted,
        email, login_id, password, nick_name, birth_date,
        gender, profile_image, region_id, state, level
    )
    SELECT
        NOW(), NOW(), FALSE,
        CONCAT('seed_user_', s.n, '@dodream.test'),
        CONCAT('seed_user_', s.n),
        /* BCrypt hash for raw password: "password" */
        '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy',
        CONCAT('seed_nick_', s.n),
        DATE_ADD('1985-01-01', INTERVAL MOD(s.n, 12000) DAY),
        CASE WHEN MOD(s.n, 2) = 0 THEN 'MALE' ELSE 'FEMALE' END,
        NULL,
        v_region_id,
        'ACTIVE',
        CASE MOD(s.n, 3)
            WHEN 0 THEN 'SEED'
            WHEN 1 THEN 'SPROUT'
            ELSE 'TREE'
        END
    FROM perf_seed_seq s
    WHERE s.n <= v_member_target
    ORDER BY s.n;

    /* Todo groups with top-20 job concentration */
    INSERT INTO todo_group (
        created_at, updated_at, deleted, job_id, member_id, total_view
    )
    SELECT
        NOW(), NOW(), FALSE,
        CASE
            WHEN s.n <= FLOOR(v_group_target * 0.70)
                THEN 1 + MOD(s.n - 1, LEAST(20, v_job_target))
            ELSE 1 + MOD(s.n - 1, v_job_target)
        END AS job_id,
        1 + MOD(s.n - 1, v_member_target) AS member_id,
        MOD(s.n * 13, 5000)
    FROM perf_seed_seq s
    WHERE s.n <= v_group_target
    ORDER BY s.n;

    /* Plan table: top 5% groups => 80~100, others => 20~30 */
    DROP TEMPORARY TABLE IF EXISTS tmp_group_plan;
    CREATE TEMPORARY TABLE tmp_group_plan (
        group_id BIGINT PRIMARY KEY,
        grp_rank INT NOT NULL,
        todo_cnt INT NOT NULL
    ) ENGINE=Memory;

    INSERT INTO tmp_group_plan (group_id, grp_rank, todo_cnt)
    SELECT
        t.id,
        t.rn,
        CASE
            WHEN t.rn <= v_heavy_group_target THEN 80 + MOD(t.rn, 21)
            ELSE 20 + MOD(t.rn, 11)
        END AS todo_cnt
    FROM (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn
        FROM todo_group
    ) t;

    /* Base todos (other_todo_id = 0) */
    INSERT INTO todo (
        created_at, updated_at, deleted,
        todo_group_id, member_id, title, save_count, completed, other_todo_id
    )
    SELECT
        NOW(), NOW(), FALSE,
        gp.group_id,
        tg.member_id,
        CONCAT('BASE_TODO_G', gp.group_id, '_', s.n),
        0,
        FALSE,
        0
    FROM tmp_group_plan gp
    JOIN todo_group tg ON tg.id = gp.group_id
    JOIN perf_seed_seq s ON s.n <= gp.todo_cnt
    ORDER BY gp.group_id, s.n;

    /* Reference table for stable random source selection */
    DROP TEMPORARY TABLE IF EXISTS tmp_base_todo_ref;
    CREATE TEMPORARY TABLE tmp_base_todo_ref (
        seq INT PRIMARY KEY,
        todo_id BIGINT NOT NULL
    ) ENGINE=InnoDB;

    INSERT INTO tmp_base_todo_ref (seq, todo_id)
    SELECT
        ROW_NUMBER() OVER (ORDER BY t.id) AS seq,
        t.id
    FROM todo t
    WHERE t.other_todo_id = 0;

    SET v_base_todo_count = (SELECT COUNT(*) FROM tmp_base_todo_ref);

    /* Member-owned groups for distributing saved todos */
    DROP TEMPORARY TABLE IF EXISTS tmp_member_groups;
    CREATE TEMPORARY TABLE tmp_member_groups (
        member_id BIGINT NOT NULL,
        group_id BIGINT NOT NULL,
        grp_ord INT NOT NULL,
        grp_cnt INT NOT NULL,
        PRIMARY KEY (member_id, grp_ord),
        KEY idx_mg_group_id (group_id)
    ) ENGINE=InnoDB;

    INSERT INTO tmp_member_groups (member_id, group_id, grp_ord, grp_cnt)
    SELECT
        x.member_id,
        x.group_id,
        x.grp_ord,
        x.grp_cnt
    FROM (
        SELECT
            tg.member_id,
            tg.id AS group_id,
            ROW_NUMBER() OVER (PARTITION BY tg.member_id ORDER BY tg.id) AS grp_ord,
            COUNT(*) OVER (PARTITION BY tg.member_id) AS grp_cnt
        FROM todo_group tg
    ) x;

    DROP TEMPORARY TABLE IF EXISTS tmp_heavy_member_plan;
    CREATE TEMPORARY TABLE tmp_heavy_member_plan (
        member_id BIGINT PRIMARY KEY,
        saved_cnt INT NOT NULL
    ) ENGINE=Memory;

    INSERT INTO tmp_heavy_member_plan (member_id, saved_cnt)
    SELECT
        x.member_id,
        300 + MOD(x.rn * 37, 701) AS saved_cnt
    FROM (
        SELECT id AS member_id, ROW_NUMBER() OVER (ORDER BY id) AS rn
        FROM member
    ) x
    WHERE x.rn <= v_heavy_member_target;

    /* Saved-other todo rows (other_todo_id > 0) */
    INSERT INTO todo (
        created_at, updated_at, deleted,
        todo_group_id, member_id, title, save_count, completed, other_todo_id
    )
    SELECT
        NOW(), NOW(), FALSE,
        mg.group_id,
        hm.member_id,
        CONCAT('SAVED_TODO_M', hm.member_id, '_', s.n),
        0,
        FALSE,
        b.todo_id
    FROM tmp_heavy_member_plan hm
    JOIN perf_seed_seq s ON s.n <= hm.saved_cnt
    JOIN tmp_member_groups mg
      ON mg.member_id = hm.member_id
     AND mg.grp_ord = 1 + MOD(s.n - 1, mg.grp_cnt)
    JOIN tmp_base_todo_ref b
      ON b.seq = 1 + MOD((hm.member_id * 131 + s.n * 17), v_base_todo_count)
    ORDER BY hm.member_id, s.n;

    /* Reflect saved count to source todos */
    UPDATE todo t
    JOIN (
        SELECT other_todo_id, COUNT(*) AS cnt
        FROM todo
        WHERE other_todo_id > 0
        GROUP BY other_todo_id
    ) x ON x.other_todo_id = t.id
    SET t.save_count = x.cnt;

    /* Recruit scraps */
    INSERT INTO member_recruit_scrap (
        created_at, updated_at, deleted,
        recruit_id, title, company_name, expiration_date, location_name,
        job_type, experience_level, education_level, close_type, recruit_url, member_id
    )
    SELECT
        NOW(), NOW(), FALSE,
        CONCAT('R-', LPAD(s.n, 10, '0')),
        CONCAT('Seed Recruit Title ', s.n),
        CONCAT('Seed Company ', 1 + MOD(s.n, 2000)),
        DATE_FORMAT(DATE_ADD(CURDATE(), INTERVAL MOD(s.n, 90) DAY), '%Y-%m-%dT00:00:00+0900'),
        CONCAT('Region-', 1 + MOD(s.n, 20)),
        'FULL_TIME',
        CASE MOD(s.n, 3)
            WHEN 0 THEN 'ENTRY'
            WHEN 1 THEN 'EXPERIENCED'
            ELSE 'ANY'
        END,
        'NO_DEGREE',
        CASE MOD(s.n, 4)
            WHEN 0 THEN 'SPECIFIC_DATE'
            WHEN 1 THEN 'UNTIL_FILLED'
            WHEN 2 THEN 'ALWAYS_OPEN'
            ELSE 'OCCASIONAL'
        END,
        CONCAT('https://seed.local/recruit/', s.n),
        1 + MOD(s.n - 1, v_member_target)
    FROM perf_seed_seq s
    WHERE s.n <= v_recruit_scrap_target
    ORDER BY s.n;

    /* Training scraps */
    INSERT INTO member_training_scrap (
        created_at, updated_at, deleted,
        training_id, training_name, training_org_name, training_org_addr,
        training_start_date, training_end_date, training_degree, training_manage, training_url, member_id
    )
    SELECT
        NOW(), NOW(), FALSE,
        CONCAT('T-', LPAD(s.n, 10, '0')),
        CONCAT('Seed Training ', s.n),
        CONCAT('Seed Org ', 1 + MOD(s.n, 3000)),
        CONCAT('Seoul-', 1 + MOD(s.n, 25)),
        DATE_ADD(CURDATE(), INTERVAL MOD(s.n, 30) DAY),
        DATE_ADD(CURDATE(), INTERVAL 30 + MOD(s.n, 120) DAY),
        CAST(1 + MOD(s.n, 10) AS CHAR),
        100000 + MOD(s.n * 97, 900000),
        CONCAT('https://seed.local/training/', s.n),
        1 + MOD(s.n - 1, v_member_target)
    FROM perf_seed_seq s
    WHERE s.n <= v_training_scrap_target
    ORDER BY s.n;

    /* Synchronize job.todo_group_num */
    UPDATE job SET todo_group_num = 0;
    UPDATE job j
    JOIN (
        SELECT job_id, COUNT(*) AS c
        FROM todo_group
        GROUP BY job_id
    ) x ON x.job_id = j.id
    SET j.todo_group_num = x.c;

    ANALYZE TABLE member, job, todo_group, todo, member_recruit_scrap, member_training_scrap;

    /* Summary */
    SELECT 'scale' AS metric, v_scale AS value
    UNION ALL SELECT 'member_count', CAST((SELECT COUNT(*) FROM member) AS CHAR)
    UNION ALL SELECT 'job_count', CAST((SELECT COUNT(*) FROM job) AS CHAR)
    UNION ALL SELECT 'todo_group_count', CAST((SELECT COUNT(*) FROM todo_group) AS CHAR)
    UNION ALL SELECT 'todo_total_count', CAST((SELECT COUNT(*) FROM todo) AS CHAR)
    UNION ALL SELECT 'todo_base_count', CAST((SELECT COUNT(*) FROM todo WHERE other_todo_id = 0) AS CHAR)
    UNION ALL SELECT 'todo_saved_count', CAST((SELECT COUNT(*) FROM todo WHERE other_todo_id > 0) AS CHAR)
    UNION ALL SELECT 'member_recruit_scrap_count', CAST((SELECT COUNT(*) FROM member_recruit_scrap) AS CHAR)
    UNION ALL SELECT 'member_training_scrap_count', CAST((SELECT COUNT(*) FROM member_training_scrap) AS CHAR);

    /* Distribution checks */
    SELECT
        'heavy_member_saved_todo_min_max' AS check_name,
        MIN(saved_cnt) AS min_saved_cnt,
        MAX(saved_cnt) AS max_saved_cnt
    FROM (
        SELECT t.member_id, COUNT(*) AS saved_cnt
        FROM todo t
        WHERE t.other_todo_id > 0
        GROUP BY t.member_id
        ORDER BY saved_cnt DESC
        LIMIT v_heavy_member_target
    ) d;

    SELECT
        'todo_per_group_top5pct_min_max' AS check_name,
        MIN(todo_cnt) AS min_todo_cnt,
        MAX(todo_cnt) AS max_todo_cnt
    FROM (
        SELECT tg.id, COUNT(t.id) AS todo_cnt
        FROM todo_group tg
        LEFT JOIN todo t ON t.todo_group_id = tg.id AND t.other_todo_id = 0
        GROUP BY tg.id
        ORDER BY todo_cnt DESC
        LIMIT v_heavy_group_target
    ) g;
END $$
DELIMITER ;

CALL sp_seed_perf(@seed_scale);

