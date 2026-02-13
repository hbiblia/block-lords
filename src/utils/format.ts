/**
 * Currency and number formatting utilities
 */

/**
 * Format a number with thousands separators
 * @param value - The number to format
 * @param decimals - Number of decimal places (default: 0)
 * @returns Formatted string with thousands separators
 */
export function formatNumber(value: number | string | undefined | null, decimals: number = 0): string {
  if (value === undefined || value === null) {
    return decimals > 0 ? '0.' + '0'.repeat(decimals) : '0';
  }

  // Convert string to number if needed (handles DB NUMERIC type)
  const numValue = typeof value === 'string' ? parseFloat(value) : value;

  if (isNaN(numValue)) {
    return decimals > 0 ? '0.' + '0'.repeat(decimals) : '0';
  }

  // Round to avoid floating point issues
  const rounded = decimals === 0 ? Math.round(numValue) : numValue;

  return rounded.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

/**
 * Format GameCoin balance (compact for large numbers)
 */
export function formatGamecoin(value: number | undefined | null): string {
  if (value === undefined || value === null) return '0';
  const v = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(v)) return '0';
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(1).replace(/\.0$/, '') + 'M';
  if (v >= 1_000) return (v / 1_000).toFixed(1).replace(/\.0$/, '') + 'k';
  return formatNumber(v, 0);
}

/**
 * Format Crypto balance (compact for large numbers, 2 decimals for small)
 */
export function formatCrypto(value: number | undefined | null): string {
  if (value === undefined || value === null) return '0.00';
  const v = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(v)) return '0.00';
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(1).replace(/\.0$/, '') + 'M';
  if (v >= 1_000) return (v / 1_000).toFixed(1).replace(/\.0$/, '') + 'k';
  return formatNumber(v, 2);
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
    return (value / 1_000).toFixed(1) + 'k';
  }
  return formatNumber(value, 0);
}
