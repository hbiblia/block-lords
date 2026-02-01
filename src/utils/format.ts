/**
 * Currency and number formatting utilities
 */

/**
 * Format a number with thousands separators
 * @param value - The number to format
 * @param decimals - Number of decimal places (default: 0)
 * @returns Formatted string with thousands separators
 */
export function formatNumber(value: number | undefined | null, decimals: number = 0): string {
  if (value === undefined || value === null || isNaN(value)) {
    return decimals > 0 ? '0.' + '0'.repeat(decimals) : '0';
  }

  return value.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

/**
 * Format GameCoin balance (no decimals for display, but with thousands separators)
 */
export function formatGamecoin(value: number | undefined | null): string {
  return formatNumber(value, 0);
}

/**
 * Format Crypto balance (2 decimals with thousands separators)
 */
export function formatCrypto(value: number | undefined | null): string {
  return formatNumber(value, 2);
}

/**
 * Format RON balance (4 decimals for precision)
 */
export function formatRon(value: number | undefined | null): string {
  return formatNumber(value, 4);
}

/**
 * Format hashrate with H/s suffix
 */
export function formatHashrate(value: number | undefined | null): string {
  return formatNumber(value, 0) + ' H/s';
}

/**
 * Compact format for large numbers (e.g., 1.5K, 2.3M)
 */
export function formatCompact(value: number | undefined | null): string {
  if (value === undefined || value === null || isNaN(value)) {
    return '0';
  }

  if (value >= 1_000_000) {
    return (value / 1_000_000).toFixed(1) + 'M';
  }
  if (value >= 1_000) {
    return (value / 1_000).toFixed(1) + 'K';
  }
  return formatNumber(value, 0);
}
