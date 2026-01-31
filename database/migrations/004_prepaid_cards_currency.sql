-- =====================================================
-- BLOCK LORDS - Add currency to prepaid cards
-- =====================================================
-- Ejecutar después de 003_prepaid_cards.sql

-- Add currency column to prepaid_cards (default to gamecoin for backward compatibility)
ALTER TABLE prepaid_cards
ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'gamecoin'
CHECK (currency IN ('gamecoin', 'crypto'));
