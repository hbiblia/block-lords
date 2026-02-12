-- =====================================================
-- BLOCK LORDS - Mission Data
-- =====================================================
-- Safe to run multiple times (uses ON CONFLICT)
-- Translations handled in frontend: t(`missions.items.${id}.name`)

-- =====================================================
-- DAILY MISSIONS - EASY
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('daily_mine_1', 'daily_mine_1', 'daily_mine_1', 'mine_blocks', 1, 'gamecoin', 100, 'easy', '⛏️', 'daily'),
  ('daily_mine_3', 'daily_mine_3', 'daily_mine_3', 'mine_blocks', 3, 'gamecoin', 250, 'easy', '⛏️', 'daily'),
  ('daily_online_15', 'daily_online_15', 'daily_online_15', 'online_time', 15, 'gamecoin', 80, 'easy', '🌐', 'daily'),
  ('daily_online_30', 'daily_online_30', 'daily_online_30', 'online_time', 30, 'gamecoin', 150, 'easy', '🌐', 'daily'),
  ('daily_earn_100', 'daily_earn_100', 'daily_earn_100', 'earn_crypto', 100, 'gamecoin', 120, 'easy', '💰', 'daily'),
  ('daily_earn_500', 'daily_earn_500', 'daily_earn_500', 'earn_crypto', 500, 'energy', 15, 'easy', '💰', 'daily'),
  ('daily_start_rig', 'daily_start_rig', 'daily_start_rig', 'start_rig', 1, 'gamecoin', 50, 'easy', '🔌', 'daily'),
  ('daily_active_60', 'daily_active_60', 'daily_active_60', 'rig_active_time', 60, 'gamecoin', 200, 'easy', '⚡', 'daily'),
  ('daily_recharge', 'daily_recharge', 'daily_recharge', 'use_prepaid_card', 1, 'gamecoin', 100, 'easy', '🔋', 'daily'),
  ('recharge_once', 'recharge_once', 'recharge_once', 'use_prepaid_card', 1, 'gamecoin', 100, 'easy', '🔋', 'daily')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;

-- =====================================================
-- DAILY MISSIONS - MEDIUM
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('daily_mine_5', 'daily_mine_5', 'daily_mine_5', 'mine_blocks', 5, 'crypto', 50, 'medium', '⛏️', 'daily'),
  ('daily_mine_8', 'daily_mine_8', 'daily_mine_8', 'mine_blocks', 8, 'crypto', 150, 'medium', '🔨', 'daily'),
  ('daily_online_60', 'daily_online_60', 'daily_online_60', 'online_time', 60, 'energy', 25, 'medium', '⏰', 'daily'),
  ('daily_online_120', 'daily_online_120', 'daily_online_120', 'online_time', 120, 'internet', 30, 'medium', '🏃', 'daily'),
  ('daily_earn_1000', 'daily_earn_1000', 'daily_earn_1000', 'earn_crypto', 1000, 'gamecoin', 500, 'medium', '💵', 'daily'),
  ('daily_earn_2500', 'daily_earn_2500', 'daily_earn_2500', 'earn_crypto', 2500, 'energy', 35, 'medium', '📈', 'daily'),
  ('daily_repair', 'daily_repair', 'daily_repair', 'repair_rig', 1, 'gamecoin', 300, 'medium', '🔧', 'daily'),
  ('daily_upgrade', 'daily_upgrade', 'daily_upgrade', 'upgrade_rig', 1, 'crypto', 75, 'medium', '⬆️', 'daily'),
  ('daily_trade', 'daily_trade', 'daily_trade', 'market_trade', 1, 'gamecoin', 400, 'medium', '🏪', 'daily')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;

-- =====================================================
-- DAILY MISSIONS - HARD
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('daily_mine_10', 'daily_mine_10', 'daily_mine_10', 'mine_blocks', 10, 'crypto', 400, 'hard', '💎', 'daily'),
  ('daily_mine_15', 'daily_mine_15', 'daily_mine_15', 'mine_blocks', 15, 'crypto', 800, 'hard', '🏆', 'daily'),
  ('daily_online_240', 'daily_online_240', 'daily_online_240', 'online_time', 240, 'crypto', 200, 'hard', '🎖️', 'daily'),
  ('daily_online_360', 'daily_online_360', 'daily_online_360', 'online_time', 360, 'crypto', 350, 'hard', '💪', 'daily'),
  ('daily_earn_5000', 'daily_earn_5000', 'daily_earn_5000', 'earn_crypto', 5000, 'gamecoin', 1500, 'hard', '🤑', 'daily'),
  ('daily_earn_10000', 'daily_earn_10000', 'daily_earn_10000', 'earn_crypto', 10000, 'energy', 50, 'hard', '🎰', 'daily'),
  ('daily_multi_rig', 'daily_multi_rig', 'daily_multi_rig', 'multi_rig', 2, 'crypto', 300, 'hard', '🖥️', 'daily')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;

-- =====================================================
-- DAILY MISSIONS - EPIC
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('daily_mine_20', 'daily_mine_20', 'daily_mine_20', 'mine_blocks', 20, 'crypto', 1500, 'epic', '👑', 'daily'),
  ('daily_mine_30', 'daily_mine_30', 'daily_mine_30', 'mine_blocks', 30, 'crypto', 5000, 'epic', '🌟', 'daily'),
  ('daily_online_480', 'daily_online_480', 'daily_online_480', 'online_time', 480, 'crypto', 600, 'epic', '🔥', 'daily'),
  ('daily_earn_25000', 'daily_earn_25000', 'daily_earn_25000', 'earn_crypto', 25000, 'crypto', 1000, 'epic', '💎', 'daily'),
  ('daily_earn_50000', 'daily_earn_50000', 'daily_earn_50000', 'earn_crypto', 50000, 'crypto', 2500, 'epic', '🏛️', 'daily'),
  ('daily_perfect', 'daily_perfect', 'daily_perfect', 'complete_easy_missions', 5, 'crypto', 750, 'epic', '✨', 'daily'),
  ('daily_all_rigs', 'daily_all_rigs', 'daily_all_rigs', 'multi_rig_time', 3, 'crypto', 1200, 'epic', '🏭', 'daily')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;

-- =====================================================
-- WEEKLY MISSIONS
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('weekly_mine_25', 'weekly_mine_25', 'weekly_mine_25', 'mine_blocks_weekly', 25, 'crypto', 500, 'easy', '📅', 'weekly'),
  ('weekly_online_300', 'weekly_online_300', 'weekly_online_300', 'online_time_weekly', 300, 'gamecoin', 1000, 'easy', '🗓️', 'weekly'),
  ('weekly_login_5', 'weekly_login_5', 'weekly_login_5', 'daily_login', 5, 'energy', 50, 'easy', '📆', 'weekly'),
  ('weekly_mine_75', 'weekly_mine_75', 'weekly_mine_75', 'mine_blocks_weekly', 75, 'crypto', 1500, 'medium', '⛏️', 'weekly'),
  ('weekly_earn_25000', 'weekly_earn_25000', 'weekly_earn_25000', 'earn_crypto_weekly', 25000, 'gamecoin', 3000, 'medium', '💰', 'weekly'),
  ('weekly_trades_5', 'weekly_trades_5', 'weekly_trades_5', 'market_trades_weekly', 5, 'crypto', 400, 'medium', '🏪', 'weekly'),
  ('weekly_mine_80', 'weekly_mine_80', 'weekly_mine_80', 'mine_blocks_weekly', 80, 'crypto', 4000, 'hard', '🔨', 'weekly'),
  ('weekly_earn_100000', 'weekly_earn_100000', 'weekly_earn_100000', 'earn_crypto_weekly', 100000, 'crypto', 5000, 'hard', '🤑', 'weekly'),
  ('weekly_login_7', 'weekly_login_7', 'weekly_login_7', 'daily_login', 7, 'crypto', 750, 'hard', '🏆', 'weekly'),
  ('weekly_mine_150', 'weekly_mine_150', 'weekly_mine_150', 'mine_blocks_weekly', 150, 'crypto', 10000, 'epic', '👑', 'weekly'),
  ('weekly_perfect', 'weekly_perfect', 'weekly_perfect', 'perfect_week', 7, 'crypto', 7500, 'epic', '🌟', 'weekly')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;

-- =====================================================
-- ACHIEVEMENTS (One-time)
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('achievement_first_block', 'achievement_first_block', 'achievement_first_block', 'first_block', 1, 'gamecoin', 500, 'easy', '🎉', 'achievement'),
  ('achievement_first_trade', 'achievement_first_trade', 'achievement_first_trade', 'first_trade', 1, 'gamecoin', 300, 'easy', '🤝', 'achievement'),
  ('achievement_first_upgrade', 'achievement_first_upgrade', 'achievement_first_upgrade', 'first_upgrade', 1, 'gamecoin', 400, 'easy', '⬆️', 'achievement'),
  ('achievement_first_rig', 'achievement_first_rig', 'achievement_first_rig', 'buy_rig', 1, 'crypto', 100, 'easy', '🖥️', 'achievement'),
  ('achievement_mine_100', 'achievement_mine_100', 'achievement_mine_100', 'total_blocks', 100, 'crypto', 500, 'medium', '💯', 'achievement'),
  ('achievement_mine_500', 'achievement_mine_500', 'achievement_mine_500', 'total_blocks', 500, 'crypto', 2000, 'medium', '🎯', 'achievement'),
  ('achievement_mine_1000', 'achievement_mine_1000', 'achievement_mine_1000', 'total_blocks', 1000, 'crypto', 5000, 'hard', '🏅', 'achievement'),
  ('achievement_mine_5000', 'achievement_mine_5000', 'achievement_mine_5000', 'total_blocks', 5000, 'crypto', 15000, 'hard', '🎖️', 'achievement'),
  ('achievement_mine_10000', 'achievement_mine_10000', 'achievement_mine_10000', 'total_blocks', 10000, 'crypto', 50000, 'epic', '👑', 'achievement'),
  ('achievement_earn_10000', 'achievement_earn_10000', 'achievement_earn_10000', 'total_crypto', 10000, 'gamecoin', 1000, 'easy', '💵', 'achievement'),
  ('achievement_earn_100000', 'achievement_earn_100000', 'achievement_earn_100000', 'total_crypto', 100000, 'gamecoin', 5000, 'medium', '💰', 'achievement'),
  ('achievement_earn_1000000', 'achievement_earn_1000000', 'achievement_earn_1000000', 'total_crypto', 1000000, 'crypto', 10000, 'hard', '🤑', 'achievement'),
  ('achievement_earn_10000000', 'achievement_earn_10000000', 'achievement_earn_10000000', 'total_crypto', 10000000, 'crypto', 100000, 'epic', '🏛️', 'achievement'),
  ('achievement_own_3_rigs', 'achievement_own_3_rigs', 'achievement_own_3_rigs', 'own_rigs', 3, 'crypto', 1000, 'medium', '🖥️', 'achievement'),
  ('achievement_own_5_rigs', 'achievement_own_5_rigs', 'achievement_own_5_rigs', 'own_rigs', 5, 'crypto', 3000, 'hard', '🏭', 'achievement'),
  ('achievement_own_all_rigs', 'achievement_own_all_rigs', 'achievement_own_all_rigs', 'own_rigs', 8, 'crypto', 25000, 'epic', '🏆', 'achievement'),
  ('achievement_max_upgrade', 'achievement_max_upgrade', 'achievement_max_upgrade', 'max_upgrade', 1, 'crypto', 2000, 'hard', '⭐', 'achievement'),
  ('achievement_full_upgrades', 'achievement_full_upgrades', 'achievement_full_upgrades', 'full_upgrades', 1, 'crypto', 10000, 'epic', '💎', 'achievement'),
  ('achievement_premium', 'achievement_premium', 'achievement_premium', 'first_premium', 1, 'crypto', 5000, 'medium', '⭐', 'achievement'),
  ('achievement_streak_7', 'achievement_streak_7', 'achievement_streak_7', 'login_streak', 7, 'crypto', 500, 'easy', '🔥', 'achievement'),
  ('achievement_streak_30', 'achievement_streak_30', 'achievement_streak_30', 'login_streak', 30, 'crypto', 3000, 'hard', '🔥', 'achievement'),
  ('achievement_streak_100', 'achievement_streak_100', 'achievement_streak_100', 'login_streak', 100, 'crypto', 15000, 'epic', '🔥', 'achievement')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;

-- =====================================================
-- SPECIAL / EVENT MISSIONS
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('tutorial_start', 'tutorial_start', 'tutorial_start', 'tutorial', 1, 'gamecoin', 1000, 'easy', '📚', 'event'),
  ('tutorial_first_mine', 'tutorial_first_mine', 'tutorial_first_mine', 'tutorial_mine', 1, 'energy', 50, 'easy', '🎓', 'event'),
  ('referral_1', 'referral_1', 'referral_1', 'referrals', 1, 'crypto', 1000, 'easy', '👥', 'event'),
  ('referral_5', 'referral_5', 'referral_5', 'referrals', 5, 'crypto', 7500, 'medium', '👥', 'event'),
  ('referral_10', 'referral_10', 'referral_10', 'referrals', 10, 'crypto', 20000, 'hard', '🌟', 'event'),
  ('event_weekend_warrior', 'event_weekend_warrior', 'event_weekend_warrior', 'event_blocks', 50, 'crypto', 2000, 'medium', '🎊', 'event'),
  ('event_double_xp', 'event_double_xp', 'event_double_xp', 'event_crypto', 50000, 'crypto', 5000, 'hard', '✨', 'event'),
  ('event_community', 'event_community', 'event_community', 'community_goal', 1, 'crypto', 10000, 'epic', '🌍', 'event')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;

-- =====================================================
-- ADDITIONAL MISSIONS
-- =====================================================
INSERT INTO missions (id, name, description, mission_type, target_value, reward_type, reward_amount, difficulty, icon, category)
VALUES
  ('repair_2_rigs', 'repair_2_rigs', 'repair_2_rigs', 'repair_rig', 2, 'gamecoin', 500, 'medium', '🔧', 'daily'),
  ('repair_3_rigs', 'repair_3_rigs', 'repair_3_rigs', 'repair_rig', 3, 'gamecoin', 600, 'hard', '🔧', 'daily'),
  ('use_boost_1', 'use_boost_1', 'use_boost_1', 'use_boost', 1, 'gamecoin', 300, 'medium', '🚀', 'daily'),
  ('use_cooling_2', 'use_cooling_2', 'use_cooling_2', 'install_cooling', 2, 'energy', 30, 'medium', '❄️', 'daily')
ON CONFLICT (id) DO UPDATE SET
  mission_type = EXCLUDED.mission_type,
  target_value = EXCLUDED.target_value,
  reward_type = EXCLUDED.reward_type,
  reward_amount = EXCLUDED.reward_amount,
  difficulty = EXCLUDED.difficulty,
  icon = EXCLUDED.icon,
  category = EXCLUDED.category;
