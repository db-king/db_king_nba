-- ALTER TABLE pbp_stage0 ADD COLUMN game_date DATE DEFAULT NULL;

-- This is a lot of writing!
-- SELECT STR_TO_DATE(SUBSTR(pbp_data, 1, LOCATE('\n', pbp_data)-1), '%M %d, %Y'), SUBSTR(pbp_data, LOCATE('\n', pbp_data)+1) FROM pbp_stage0 LIMIT 1;

DROP FUNCTION IF EXISTS peel_first;
DROP FUNCTION IF EXISTS remainder_after_peeling;
DROP PROCEDURE IF EXISTS runsql;
DROP PROCEDURE IF EXISTS peel_and_create;

DELIMITER $$

CREATE FUNCTION peel_first (data LONGTEXT, delim CHAR(2))
RETURNS LONGTEXT DETERMINISTIC
RETURN SUBSTR(data, 1, LOCATE(delim, data)-1);$$

CREATE FUNCTION remainder_after_peeling (data longtext, delim CHAR(2))
RETURNS LONGTEXT DETERMINISTIC
RETURN SUBSTR(data, LOCATE(delim, data)+1);$$

-- A little better.
-- Let's combine these functions in a dynamic procedure

CREATE PROCEDURE runsql (sqlstr LONGTEXT)
BEGIN
  set @sqlstr = sqlstr;
	PREPARE stmt FROM @sqlstr;
	EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
END$$

CREATE PROCEDURE peel_and_create (
	IN tbl_name CHAR(30),
	IN old_col CHAR(30), 
	IN new_col CHAR(30), 
	IN col_type CHAR(30),
	IN delim CHAR(5),
	IN func_start CHAR(50),
	IN func_end CHAR(50)
)
BEGIN
	set @quoted_delim = CONCAT("'", delim, "'");
	set @comma = ',';

	-- CREATE NEW COLUMN
	CALL runsql(CONCAT_WS(' ', 'ALTER TABLE', tbl_name, 'ADD COLUMN', new_col, col_type, 'DEFAULT NULL'));

	CALL runsql(
		CONCAT_WS(' ',
			'UPDATE', tbl_name, 
			'SET', new_col, '=', func_start, 'peel_first(', old_col, @comma, @quoted_delim, ')', func_end, @comma,
			 old_col, '=', 'remainder_after_peeling(', old_col, @comma, @quoted_delim, ')', ';'
		)
	);
END$$

DELIMITER ;

-- UPDATE  pbp_stage0 
-- SET game_date = STR_TO_DATE(peel_first(pbp_data, '\n'), '%M %d, %Y'), 
--    pbp_data = remainder_after_peeling(pbp_data, '\n');


-- Split out different team data
CALL peel_and_create('pbp_stage0', 'pbp_data', 'game_date', 'DATE', '\n', 'STR_TO_DATE(', ', "%M %d, %Y")');
CALL peel_and_create('pbp_stage0', 'pbp_data', 'team1_data', 'LONGTEXT', '\n', '(', ')');
CALL peel_and_create('pbp_stage0', 'pbp_data', 'team2_data', 'LONGTEXT', '\n', '(', ')');

CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_location', 'CHAR(50)', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_code', 'CHAR(10)', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_record', 'CHAR(5)', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_record_away', 'CHAR(15)', ',', 'TRIM(REPLACE(', ', "Away", ""))');

CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_location', 'CHAR(50)', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_code', 'CHAR(10)', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_record', 'CHAR(5)', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_record_home', 'CHAR(15)', ',', 'TRIM(REPLACE(', ', "Home", ""))');

CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_final_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_final_score', 'INT', ',', null, null);

CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_q1_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_q2_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_q3_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team1_data', 'team1_q4_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_q1_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_q2_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_q3_score', 'INT', ',', null, null);
CALL peel_and_create('pbp_stage0', 'team2_data', 'team2_q4_score', 'INT', ',', null, null);

-- Scores problem...
-- There can be overtimes. So, maybe we want more than 4 columns now.
-- This is a sign of bad database design. But we're only worrying about atomicity right now.

DELIMITER $$

DROP PROCEDURE IF EXISTS get_overtimes$$

CREATE PROCEDURE get_overtimes ()
BEGIN
  DECLARE pos INT DEFAULT 0;

  SELECT @newot := COUNT(*) FROM pbp_stage0 WHERE NOT LOCATE('.', peel_first(team1_data, ','));
  WHILE @newot > 1 DO
   SET pos = pos + 1;
   call runsql(CONCAT('ALTER TABLE pbp_stage0 ADD COLUMN team1_ot', pos, ' INT DEFAULT NULL;'));
   call runsql(CONCAT('ALTER TABLE pbp_stage0 ADD COLUMN team2_ot', pos, ' INT DEFAULT NULL;'));
   call runsql(CONCAT('UPDATE pbp_stage0 
        SET team1_ot', pos, '= peel_first(team1_data, \',\'), ',
           'team2_ot', pos, '= peel_first(team2_data, \',\'), ',
           'team1_data = remainder_after_peeling(team1_data, \',\'), ',
           'team2_data = remainder_after_peeling(team2_data, \',\') ',
      'WHERE NOT LOCATE(\'.\', peel_first(team1_data, \',\'))'));
           
  SELECT @newot := COUNT(*) FROM pbp_stage0 WHERE NOT LOCATE('.', peel_first(team1_data, ','));

  END WHILE;


END$$

DELIMITER ;

CALL get_overtimes();
