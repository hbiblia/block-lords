-- =====================================================
-- BLOCK LORDS - Mission Data
-- =====================================================
-- Safe to run multiple times (uses ON CONFLICT)
-- Translations handled in frontend: t(`missions.items.${id}.name`)

-- =====================================================
-- DAILY MISSIONS - EASY
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('daily_mine_1', 'daily_mine_1', 'daily_mine_1', 'mine_blocks', 1, 'gamecoin', 100, 'easy', '⛏️'),
  ('daily_mine_3', 'daily_mine_3', 'daily_mine_3', 'mine_blocks', 3, 'gamecoin', 250, 'easy', '⛏️'),
  ('daily_online_15', 'daily_online_15', 'daily_online_15', 'online_time', 15, 'gamecoin', 80, 'easy', '🌐'),
  ('daily_online_30', 'daily_online_30', 'daily_online_30', 'online_time', 30, 'gamecoin', 150, 'easy', '🌐'),
  ('daily_earn_100', 'daily_earn_100', 'daily_earn_100', 'earn_crypto', 100, 'gamecoin', 120, 'easy', '💰'),
  ('daily_earn_500', 'daily_earn_500', 'daily_earn_500', 'earn_crypto', 500, 'energy', 15, 'easy', '💰'),
  ('daily_start_rig', 'daily_start_rig', 'daily_start_rig', 'start_rig', 1, 'gamecoin', 50, 'easy', '🔌'),
  ('daily_active_60', 'daily_active_60', 'daily_active_60', 'rig_active_time', 60, 'gamecoin', 200, 'easy', '⚡')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- =====================================================
-- DAILY MISSIONS - MEDIUM
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('daily_mine_5', 'daily_mine_5', 'daily_mine_5', 'mine_blocks', 5, 'crypto', 50, 'medium', '⛏️'),
  ('daily_mine_10', 'daily_mine_10', 'daily_mine_10', 'mine_blocks', 10, 'crypto', 150, 'medium', '🔨'),
  ('daily_online_60', 'daily_online_60', 'daily_online_60', 'online_time', 60, 'energy', 25, 'medium', '⏰'),
  ('daily_online_120', 'daily_online_120', 'daily_online_120', 'online_time', 120, 'internet', 30, 'medium', '🏃'),
  ('daily_earn_1000', 'daily_earn_1000', 'daily_earn_1000', 'earn_crypto', 1000, 'gamecoin', 500, 'medium', '💵'),
  ('daily_earn_2500', 'daily_earn_2500', 'daily_earn_2500', 'earn_crypto', 2500, 'energy', 35, 'medium', '📈'),
  ('daily_repair', 'daily_repair', 'daily_repair', 'repair_rig', 1, 'gamecoin', 300, 'medium', '🔧'),
  ('daily_upgrade', 'daily_upgrade', 'daily_upgrade', 'upgrade_rig', 1, 'crypto', 75, 'medium', '⬆️'),
  ('daily_trade', 'daily_trade', 'daily_trade', 'market_trade', 1, 'gamecoin', 400, 'medium', '🏪')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- =====================================================
-- DAILY MISSIONS - HARD
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('daily_mine_20', 'daily_mine_20', 'daily_mine_20', 'mine_blocks', 20, 'crypto', 400, 'hard', '💎'),
  ('daily_mine_35', 'daily_mine_35', 'daily_mine_35', 'mine_blocks', 35, 'crypto', 800, 'hard', '🏆'),
  ('daily_online_240', 'daily_online_240', 'daily_online_240', 'online_time', 240, 'crypto', 200, 'hard', '🎖️'),
  ('daily_online_360', 'daily_online_360', 'daily_online_360', 'online_time', 360, 'crypto', 350, 'hard', '💪'),
  ('daily_earn_5000', 'daily_earn_5000', 'daily_earn_5000', 'earn_crypto', 5000, 'gamecoin', 1500, 'hard', '🤑'),
  ('daily_earn_10000', 'daily_earn_10000', 'daily_earn_10000', 'earn_crypto', 10000, 'energy', 50, 'hard', '🎰'),
  ('daily_multi_rig', 'daily_multi_rig', 'daily_multi_rig', 'multi_rig', 2, 'crypto', 300, 'hard', '🖥️'),
  ('daily_no_overheat', 'daily_no_overheat', 'daily_no_overheat', 'mine_no_overheat', 10, 'internet', 40, 'hard', '❄️')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- =====================================================
-- DAILY MISSIONS - EPIC
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('daily_mine_50', 'daily_mine_50', 'daily_mine_50', 'mine_blocks', 50, 'crypto', 1500, 'epic', '👑'),
  ('daily_mine_100', 'daily_mine_100', 'daily_mine_100', 'mine_blocks', 100, 'crypto', 5000, 'epic', '🌟'),
  ('daily_online_480', 'daily_online_480', 'daily_online_480', 'online_time', 480, 'crypto', 600, 'epic', '🔥'),
  ('daily_earn_25000', 'daily_earn_25000', 'daily_earn_25000', 'earn_crypto', 25000, 'crypto', 1000, 'epic', '💎'),
  ('daily_earn_50000', 'daily_earn_50000', 'daily_earn_50000', 'earn_crypto', 50000, 'crypto', 2500, 'epic', '🏛️'),
  ('daily_perfect', 'daily_perfect', 'daily_perfect', 'complete_easy_missions', 5, 'crypto', 750, 'epic', '✨'),
  ('daily_all_rigs', 'daily_all_rigs', 'daily_all_rigs', 'multi_rig_time', 3, 'crypto', 1200, 'epic', '🏭')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- =====================================================
-- WEEKLY MISSIONS
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('weekly_mine_25', 'weekly_mine_25', 'weekly_mine_25', 'mine_blocks_weekly', 25, 'crypto', 500, 'easy', '📅'),
  ('weekly_online_300', 'weekly_online_300', 'weekly_online_300', 'online_time_weekly', 300, 'gamecoin', 1000, 'easy', '🗓️'),
  ('weekly_login_5', 'weekly_login_5', 'weekly_login_5', 'daily_login', 5, 'energy', 50, 'easy', '📆'),
  ('weekly_mine_75', 'weekly_mine_75', 'weekly_mine_75', 'mine_blocks_weekly', 75, 'crypto', 1500, 'medium', '⛏️'),
  ('weekly_earn_25000', 'weekly_earn_25000', 'weekly_earn_25000', 'earn_crypto_weekly', 25000, 'gamecoin', 3000, 'medium', '💰'),
  ('weekly_trades_5', 'weekly_trades_5', 'weekly_trades_5', 'market_trades_weekly', 5, 'crypto', 400, 'medium', '🏪'),
  ('weekly_mine_200', 'weekly_mine_200', 'weekly_mine_200', 'mine_blocks_weekly', 200, 'crypto', 4000, 'hard', '🔨'),
  ('weekly_earn_100000', 'weekly_earn_100000', 'weekly_earn_100000', 'earn_crypto_weekly', 100000, 'crypto', 5000, 'hard', '🤑'),
  ('weekly_login_7', 'weekly_login_7', 'weekly_login_7', 'daily_login', 7, 'crypto', 750, 'hard', '🏆'),
  ('weekly_mine_500', 'weekly_mine_500', 'weekly_mine_500', 'mine_blocks_weekly', 500, 'crypto', 10000, 'epic', '👑'),
  ('weekly_perfect', 'weekly_perfect', 'weekly_perfect', 'perfect_week', 7, 'crypto', 7500, 'epic', '🌟')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- =====================================================
-- ACHIEVEMENTS (One-time)
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('achievement_first_block', 'achievement_first_block', 'achievement_first_block', 'first_block', 1, 'gamecoin', 500, 'easy', '🎉'),
  ('achievement_first_trade', 'achievement_first_trade', 'achievement_first_trade', 'first_trade', 1, 'gamecoin', 300, 'easy', '🤝'),
  ('achievement_first_upgrade', 'achievement_first_upgrade', 'achievement_first_upgrade', 'first_upgrade', 1, 'gamecoin', 400, 'easy', '⬆️'),
  ('achievement_first_rig', 'achievement_first_rig', 'achievement_first_rig', 'buy_rig', 1, 'crypto', 100, 'easy', '🖥️'),
  ('achievement_mine_100', 'achievement_mine_100', 'achievement_mine_100', 'total_blocks', 100, 'crypto', 500, 'medium', '💯'),
  ('achievement_mine_500', 'achievement_mine_500', 'achievement_mine_500', 'total_blocks', 500, 'crypto', 2000, 'medium', '🎯'),
  ('achievement_mine_1000', 'achievement_mine_1000', 'achievement_mine_1000', 'total_blocks', 1000, 'crypto', 5000, 'hard', '🏅'),
  ('achievement_mine_5000', 'achievement_mine_5000', 'achievement_mine_5000', 'total_blocks', 5000, 'crypto', 15000, 'hard', '🎖️'),
  ('achievement_mine_10000', 'achievement_mine_10000', 'achievement_mine_10000', 'total_blocks', 10000, 'crypto', 50000, 'epic', '👑'),
  ('achievement_earn_10000', 'achievement_earn_10000', 'achievement_earn_10000', 'total_crypto', 10000, 'gamecoin', 1000, 'easy', '💵'),
  ('achievement_earn_100000', 'achievement_earn_100000', 'achievement_earn_100000', 'total_crypto', 100000, 'gamecoin', 5000, 'medium', '💰'),
  ('achievement_earn_1000000', 'achievement_earn_1000000', 'achievement_earn_1000000', 'total_crypto', 1000000, 'crypto', 10000, 'hard', '🤑'),
  ('achievement_earn_10000000', 'achievement_earn_10000000', 'achievement_earn_10000000', 'total_crypto', 10000000, 'crypto', 100000, 'epic', '🏛️'),
  ('achievement_own_3_rigs', 'achievement_own_3_rigs', 'achievement_own_3_rigs', 'own_rigs', 3, 'crypto', 1000, 'medium', '🖥️'),
  ('achievement_own_5_rigs', 'achievement_own_5_rigs', 'achievement_own_5_rigs', 'own_rigs', 5, 'crypto', 3000, 'hard', '🏭'),
  ('achievement_own_all_rigs', 'achievement_own_all_rigs', 'achievement_own_all_rigs', 'own_rigs', 8, 'crypto', 25000, 'epic', '🏆'),
  ('achievement_max_upgrade', 'achievement_max_upgrade', 'achievement_max_upgrade', 'max_upgrade', 1, 'crypto', 2000, 'hard', '⭐'),
  ('achievement_full_upgrades', 'achievement_full_upgrades', 'achievement_full_upgrades', 'full_upgrades', 1, 'crypto', 10000, 'epic', '💎'),
  ('achievement_premium', 'achievement_premium', 'achievement_premium', 'first_premium', 1, 'crypto', 5000, 'medium', '⭐'),
  ('achievement_streak_7', 'achievement_streak_7', 'achievement_streak_7', 'login_streak', 7, 'crypto', 500, 'easy', '🔥'),
  ('achievement_streak_30', 'achievement_streak_30', 'achievement_streak_30', 'login_streak', 30, 'crypto', 3000, 'hard', '🔥'),
  ('achievement_streak_100', 'achievement_streak_100', 'achievement_streak_100', 'login_streak', 100, 'crypto', 15000, 'epic', '🔥')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;

-- =====================================================
-- SPECIAL / EVENT MISSIONS
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon)
VALUES
  ('tutorial_start', 'tutorial_start', 'tutorial_start', 'tutorial', 1, 'gamecoin', 1000, 'easy', '📚'),
  ('tutorial_first_mine', 'tutorial_first_mine', 'tutorial_first_mine', 'tutorial_mine', 1, 'energy', 50, 'easy', '🎓'),
  ('referral_1', 'referral_1', 'referral_1', 'referrals', 1, 'crypto', 1000, 'easy', '👥'),
  ('referral_5', 'referral_5', 'referral_5', 'referrals', 5, 'crypto', 7500, 'medium', '👥'),
  ('referral_10', 'referral_10', 'referral_10', 'referrals', 10, 'crypto', 20000, 'hard', '🌟'),
  ('event_weekend_warrior', 'event_weekend_warrior', 'event_weekend_warrior', 'event_blocks', 50, 'crypto', 2000, 'medium', '🎊'),
  ('event_double_xp', 'event_double_xp', 'event_double_xp', 'event_crypto', 50000, 'crypto', 5000, 'hard', '✨'),
  ('event_community', 'event_community', 'event_community', 'community_goal', 1, 'crypto', 10000, 'epic', '🌍')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon;
