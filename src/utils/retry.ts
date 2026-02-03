/**
 * Retry utility with exponential backoff
 * Handles transient network failures gracefully
 */

export interface RetryOptions {
  /** Maximum number of retry attempts (default: 3) */
  maxRetries?: number;
  /** Base delay in ms (default: 1000) */
  baseDelay?: number;
  /** Maximum delay in ms (default: 10000) */
  maxDelay?: number;
  /** Multiplier for exponential backoff (default: 2) */
  backoffMultiplier?: number;
  /** Function to determine if error is retryable (default: network/timeout errors) */
  isRetryable?: (error: unknown) => boolean;
  /** Callback on each retry attempt */
  onRetry?: (attempt: number, error: unknown, nextDelay: number) => void;
}

const DEFAULT_OPTIONS: Required<RetryOptions> = {
  maxRetries: 3,
  baseDelay: 1000,
  maxDelay: 10000,
  backoffMultiplier: 2,
  isRetryable: isRetryableError,
  onRetry: () => {},
};

/**
 * Default function to determine if an error is retryable
 * Retries on network errors, timeouts, and 5xx server errors
 */
export function isRetryableError(error: unknown): boolean {
  if (!error) return false;

  // Network errors
  if (error instanceof TypeError && error.message.includes('fetch')) {
    return true;
  }

  // Check for common error patterns
  const errorObj = error as Record<string, unknown>;

  // Supabase/PostgreSQL errors
  if (typeof errorObj.code === 'string') {
    const code = errorObj.code;
    // Connection errors, timeout, too many connections
    if (['PGRST301', 'PGRST502', '08000', '08003', '08006', '57P01', '53300'].includes(code)) {
      return true;
    }
  }

  // HTTP status codes
  if (typeof errorObj.status === 'number') {
    const status = errorObj.status;
    // 5xx server errors, 429 rate limit, 408 timeout
    if (status >= 500 || status === 429 || status === 408) {
      return true;
    }
  }

  // Check message for common patterns
  const message = String(errorObj.message || errorObj.error || '').toLowerCase();
  const retryablePatterns = [
    'network',
    'timeout',
    'timed out',
    'connection',
    'econnreset',
    'econnrefused',
    'socket',
    'fetch failed',
    'failed to fetch',
    'load failed',
    'abort',
    'too many',
    'rate limit',
    'temporarily unavailable',
    'service unavailable',
  ];

  return retryablePatterns.some(pattern => message.includes(pattern));
}

/**
 * Sleep for a given number of milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Calculate delay with exponential backoff and jitter
 */
function calculateDelay(attempt: number, options: Required<RetryOptions>): number {
  const exponentialDelay = options.baseDelay * Math.pow(options.backoffMultiplier, attempt);
  const cappedDelay = Math.min(exponentialDelay, options.maxDelay);
  // Add jitter (±20%) to prevent thundering herd
  const jitter = cappedDelay * 0.2 * (Math.random() * 2 - 1);
  return Math.round(cappedDelay + jitter);
}

/**
 * Execute a function with retry logic and exponential backoff
 *
 * @example
 * const data = await withRetry(() => fetchPlayerProfile(id));
 *
 * @example
 * const data = await withRetry(
 *   () => riskyOperation(),
 *   {
 *     maxRetries: 5,
 *     onRetry: (attempt, error) => console.log(`Retry ${attempt}:`, error)
 *   }
 * );
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  let lastError: unknown;

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      // Don't retry if we've exhausted attempts or error is not retryable
      if (attempt >= opts.maxRetries || !opts.isRetryable(error)) {
        throw error;
      }

      const delay = calculateDelay(attempt, opts);
      opts.onRetry(attempt + 1, error, delay);

      await sleep(delay);
    }
  }

  // This should never be reached, but TypeScript needs it
  throw lastError;
}

/**
 * Create a retryable version of an async function
 *
 * @example
 * const fetchWithRetry = createRetryable(fetchData, { maxRetries: 5 });
 * const data = await fetchWithRetry(userId);
 */
export function createRetryable<TArgs extends unknown[], TResult>(
  fn: (...args: TArgs) => Promise<TResult>,
  options: RetryOptions = {}
): (...args: TArgs) => Promise<TResult> {
  return (...args: TArgs) => withRetry(() => fn(...args), options);
}

/**
 * Execute multiple promises with retry, returning results for successful ones
 * Failed promises after all retries return null
 *
 * @example
 * const [profile, stats] = await withRetryAll([
 *   () => getProfile(id),
 *   () => getStats(id),
 * ]);
 */
export async function withRetryAll<T extends readonly (() => Promise<unknown>)[]>(
  fns: T,
  options: RetryOptions = {}
): Promise<{ [K in keyof T]: Awaited<ReturnType<T[K]>> | null }> {
  const results = await Promise.all(
    fns.map(async (fn) => {
      try {
        return await withRetry(fn, options);
      } catch {
        return null;
      }
    })
  );

  return results as { [K in keyof T]: Awaited<ReturnType<T[K]>> | null };
}

/**
 * Circuit breaker state for a specific operation
 */
interface CircuitState {
  failures: number;
  lastFailure: number;
  isOpen: boolean;
}

const circuitStates = new Map<string, CircuitState>();

/**
 * Execute with circuit breaker pattern
 * After too many failures, fast-fail without attempting the operation
 *
 * @param key Unique identifier for this circuit
 * @param fn Function to execute
 * @param options Circuit breaker options
 */
export async function withCircuitBreaker<T>(
  key: string,
  fn: () => Promise<T>,
  options: {
    failureThreshold?: number;
    resetTimeout?: number;
    fallback?: () => T | Promise<T>;
  } = {}
): Promise<T> {
  const {
    failureThreshold = 5,
    resetTimeout = 30000,
    fallback,
  } = options;

  let state = circuitStates.get(key);
  if (!state) {
    state = { failures: 0, lastFailure: 0, isOpen: false };
    circuitStates.set(key, state);
  }

  // Check if circuit should reset (half-open)
  if (state.isOpen && Date.now() - state.lastFailure > resetTimeout) {
    state.isOpen = false;
    state.failures = 0;
  }

  // If circuit is open, use fallback or throw
  if (state.isOpen) {
    if (fallback) {
      return fallback();
    }
    throw new Error(`Circuit breaker open for: ${key}`);
  }

  try {
    const result = await fn();
    // Success - reset failure count
    state.failures = 0;
    return result;
  } catch (error) {
    state.failures++;
    state.lastFailure = Date.now();

    if (state.failures >= failureThreshold) {
      state.isOpen = true;
      console.warn(`Circuit breaker opened for: ${key} after ${state.failures} failures`);
    }

    throw error;
  }
}

/**
 * Reset a specific circuit breaker
 */
export function resetCircuit(key: string): void {
  circuitStates.delete(key);
}

/**
 * Reset all circuit breakers
 */
export function resetAllCircuits(): void {
  circuitStates.clear();
}
