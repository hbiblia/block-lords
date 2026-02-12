-- =====================================================
-- FIX: Missions System - Multiple Bug Fixes
-- =====================================================
-- 1. Add 'category' column to missions table
-- 2. Fix assign_daily_missions to filter by category='daily'
-- 3. Unify claim_mission_reward (restore complete_easy_missions tracking)
-- 4. Fix get_daily_missions ordering to include 'epic'
-- 5. Add missing update_mission_progress calls (total_blocks, first_block)
-- =====================================================

-- 1) Add category column to missions table
ALTER TABLE missions ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'daily';

-- Set categories for existing missions based on their id prefix
UPDATE missions SET category = 'daily' WHERE id LIKE 'daily_%' OR id IN ('recharge_once', 'repair_2_rigs', 'repair_3_rigs', 'use_boost_1', 'use_cooling_2');
UPDATE missions SET category = 'weekly' WHERE id LIKE 'weekly_%';
UPDATE missions SET category = 'achievement' WHERE id LIKE 'achievement_%';
UPDATE missions SET category = 'event' WHERE id LIKE 'tutorial_%' OR id LIKE 'referral_%' OR id LIKE 'event_%';

-- 2) Fix assign_daily_missions to only pick from category='daily'
CREATE OR REPLACE FUNCTION assign_daily_missions(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_existing_count INTEGER;
  v_easy_mission missions%ROWTYPE;
  v_hard_mission missions%ROWTYPE;
  v_epic_mission missions%ROWTYPE;
  v_mission missions%ROWTYPE;
  v_assigned_count INTEGER := 0;
  v_epic_chance FLOAT := 0.25;
BEGIN
  SELECT COUNT(*) INTO v_existing_count
  FROM player_missions
  WHERE player_id = p_player_id AND assigned_date = v_today;

  IF v_existing_count >= 4 THEN
    RETURN json_build_object('success', true, 'message', 'Missions already assigned', 'count', v_existing_count);
  END IF;

  -- Clean up unclaimed missions from previous days
  DELETE FROM player_missions
  WHERE player_id = p_player_id
    AND assigned_date < v_today
    AND is_claimed = false;

  -- Select 1 easy daily mission
  SELECT * INTO v_easy_mission
  FROM missions
  WHERE difficulty = 'easy' AND category = 'daily'
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_easy_mission.id IS NOT NULL THEN
    INSERT INTO player_missions (player_id, mission_id, assigned_date)
    VALUES (p_player_id, v_easy_mission.id, v_today)
    ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
    v_assigned_count := v_assigned_count + 1;
  END IF;

  -- Select 2 medium daily missions
  FOR v_mission IN
    SELECT * FROM missions
    WHERE difficulty = 'medium' AND category = 'daily'
    ORDER BY RANDOM()
    LIMIT 2
  LOOP
    INSERT INTO player_missions (player_id, mission_id, assigned_date)
    VALUES (p_player_id, v_mission.id, v_today)
    ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
    v_assigned_count := v_assigned_count + 1;
  END LOOP;

  -- Select 1 hard daily mission
  SELECT * INTO v_hard_mission
  FROM missions
  WHERE difficulty = 'hard' AND category = 'daily'
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_hard_mission.id IS NOT NULL THEN
    INSERT INTO player_missions (player_id, mission_id, assigned_date)
    VALUES (p_player_id, v_hard_mission.id, v_today)
    ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
    v_assigned_count := v_assigned_count + 1;
  END IF;

  -- 25% chance for an EPIC daily mission as bonus
  IF RANDOM() < v_epic_chance THEN
    SELECT * INTO v_epic_mission
    FROM missions
    WHERE difficulty = 'epic' AND category = 'daily'
    ORDER BY RANDOM()
    LIMIT 1;

    IF v_epic_mission.id IS NOT NULL THEN
      INSERT INTO player_missions (player_id, mission_id, assigned_date)
      VALUES (p_player_id, v_epic_mission.id, v_today)
      ON CONFLICT (player_id, mission_id, assigned_date) DO NOTHING;
      v_assigned_count := v_assigned_count + 1;
    END IF;
  END IF;

  RETURN json_build_object('success', true, 'assigned', v_assigned_count);
END;
$$;

-- 3) Fix get_daily_missions ordering to include 'epic'
CREATE OR REPLACE FUNCTION get_daily_missions(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_today DATE := CURRENT_DATE;
  v_missions JSON;
  v_online_minutes INTEGER := 0;
BEGIN
  PERFORM assign_daily_missions(p_player_id);

  SELECT COALESCE(minutes_online, 0) INTO v_online_minutes
  FROM player_online_tracking
  WHERE player_id = p_player_id AND tracking_date = v_today;

  SELECT json_agg(
    json_build_object(
      'id', pm.id,
      'missionId', m.id,
      'name', m.name,
      'description', m.description,
      'missionType', m.mission_type,
      'targetValue', m.target_value,
      'progress', pm.progress,
      'isCompleted', pm.is_completed,
      'isClaimed', pm.is_claimed,
      'rewardType', m.reward_type,
      'rewardAmount', m.reward_amount,
      'difficulty', m.difficulty,
      'icon', m.icon,
      'progressPercent', LEAST(100, ROUND((pm.progress / m.target_value) * 100))
    ) ORDER BY
      CASE m.difficulty WHEN 'easy' THEN 1 WHEN 'medium' THEN 2 WHEN 'hard' THEN 3 WHEN 'epic' THEN 4 END,
      m.name
  ) INTO v_missions
  FROM player_missions pm
  JOIN missions m ON m.id = pm.mission_id
  WHERE pm.player_id = p_player_id AND pm.assigned_date = v_today;

  RETURN json_build_object(
    'success', true,
    'missions', COALESCE(v_missions, '[]'::json),
    'date', v_today,
    'onlineMinutes', v_online_minutes
  );
END;
$$;

-- 4) Unified claim_mission_reward with complete_easy_missions tracking restored
CREATE OR REPLACE FUNCTION claim_mission_reward(p_player_id UUID, p_mission_uuid UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_pm player_missions%ROWTYPE; v_mission missions%ROWTYPE; v_effective_max NUMERIC;
BEGIN
  SELECT * INTO v_pm FROM player_missions WHERE id = p_mission_uuid AND player_id = p_player_id;
  IF v_pm IS NULL THEN RETURN json_build_object('success', false, 'error', 'Mision no encontrada'); END IF;
  IF NOT v_pm.is_completed THEN RETURN json_build_object('success', false, 'error', 'No completada'); END IF;
  IF v_pm.is_claimed THEN RETURN json_build_object('success', false, 'error', 'Ya reclamada'); END IF;
  SELECT * INTO v_mission FROM missions WHERE id = v_pm.mission_id;
  IF v_mission.reward_type = 'gamecoin' THEN
    UPDATE players SET gamecoin_balance = gamecoin_balance + v_mission.reward_amount WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'crypto' THEN
    UPDATE players SET crypto_balance = crypto_balance + v_mission.reward_amount, total_crypto_earned = COALESCE(total_crypto_earned, 0) + v_mission.reward_amount WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'energy' THEN
    v_effective_max := get_effective_max_energy(p_player_id);
    UPDATE players SET energy = LEAST(v_effective_max, energy + v_mission.reward_amount) WHERE id = p_player_id;
  ELSIF v_mission.reward_type = 'internet' THEN
    v_effective_max := get_effective_max_internet(p_player_id);
    UPDATE players SET internet = LEAST(v_effective_max, internet + v_mission.reward_amount) WHERE id = p_player_id;
  END IF;
  UPDATE player_missions SET is_claimed = true, claimed_at = NOW() WHERE id = p_mission_uuid;
  INSERT INTO transactions (player_id, type, amount, currency, description) VALUES (p_player_id, 'mission_reward', v_mission.reward_amount, v_mission.reward_type, 'Mision: ' || v_mission.name);

  -- Track complete_easy_missions for the daily_perfect epic mission
  IF v_mission.difficulty = 'easy' THEN
    PERFORM update_mission_progress(p_player_id, 'complete_easy_missions', 1);
  END IF;

  RETURN json_build_object('success', true, 'rewardType', v_mission.reward_type, 'rewardAmount', v_mission.reward_amount, 'missionName', v_mission.name);
END;
$$;

-- 5) Run the updated missions_data.sql to set categories
-- (Run missions_data.sql separately after this migration)

-- 6) NOTE: The following mission_progress calls were added to all_functions.sql
-- in the block reward distribution function (distribute_block_rewards):
--   PERFORM update_mission_progress(player_id, 'total_blocks', 1);  -- for achievement_mine_* missions
--   PERFORM update_mission_progress(player_id, 'first_block', 1);   -- for achievement_first_block

-- 7) Grant permissions
GRANT EXECUTE ON FUNCTION assign_daily_missions TO authenticated;
GRANT EXECUTE ON FUNCTION get_daily_missions TO authenticated;
GRANT EXECUTE ON FUNCTION claim_mission_reward TO authenticated;
