import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Katana DEX constants for price fetching (raw RPC, no ethers needed)
const RONIN_RPC = 'https://api.roninchain.com/rpc';

// Katana V3 pool WRON/USDC 0.3% (mayor liquidez)
// token0 = USDC (0x0b...), token1 = WRON (0xe5...)
const KATANA_V3_POOL = '0x392d372f2a51610e9ac5b741379d5631ca9a1c7f';
const SLOT0_SELECTOR = '0x3850c7bd';

// Katana V2 Router (fallback)
const KATANA_V2_ROUTER = '0x7d0556d55ca1a92708681e2e231733ebd922597d';
const WRON = '0xe514d9deb7966c8be0ca922de8a064264ea6bcd4';
const USDC = '0x0b7007c13325c48911f73a2dad5fa5dcbf808adc';
const GET_AMOUNTS_OUT_SELECTOR = '0xd06ca61f';

/**
 * Fetch RON/USDC price from Katana V3 pool on-chain.
 * Uses slot0() sqrtPriceX96 from the 0.3% WRON/USDC pool.
 */
async function fetchRonPriceV3(): Promise<number> {
  const response = await fetch(RONIN_RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0', method: 'eth_call',
      params: [{ to: KATANA_V3_POOL, data: SLOT0_SELECTOR }, 'latest'], id: 1,
    }),
  });

  const result = await response.json();
  if (!result.result || result.result === '0x') {
    throw new Error('Empty slot0 response');
  }

  const hex = result.result.slice(2);
  const sqrtPriceX96 = BigInt('0x' + hex.slice(0, 64));

  // token0=USDC(6 dec), token1=WRON(18 dec)
  // raw_price = sqrtPriceX96^2 / 2^192 = WRON_raw_per_USDC_raw
  // human_price = raw_price * 10^(6-18) = WRON_per_USDC
  // RON/USDC = 1 / human_price = 2^192 * 10^12 / sqrtPriceX96^2
  // Scale by 10^8 for precision, then divide back
  const TWO_192 = BigInt(1) << BigInt(192);
  const numerator = TWO_192 * BigInt(10) ** BigInt(20);
  const priceBig = numerator / (sqrtPriceX96 * sqrtPriceX96);
  const price = Number(priceBig) / 1e8;

  if (price <= 0) throw new Error('Invalid V3 price');
  return price;
}

/**
 * Fetch RON/USDC price from Katana V2 Router (fallback).
 */
async function fetchRonPriceV2(): Promise<number> {
  const amountIn = '0x' + BigInt('1000000000000000000').toString(16).padStart(64, '0');
  const pathOffset = '0000000000000000000000000000000000000000000000000000000000000040';
  const pathLength = '0000000000000000000000000000000000000000000000000000000000000002';
  const wronPadded = '000000000000000000000000' + WRON.slice(2);
  const usdcPadded = '000000000000000000000000' + USDC.slice(2);

  const data = GET_AMOUNTS_OUT_SELECTOR + amountIn.slice(2) + pathOffset + pathLength + wronPadded + usdcPadded;

  const response = await fetch(RONIN_RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0', method: 'eth_call',
      params: [{ to: KATANA_V2_ROUTER, data }, 'latest'], id: 1,
    }),
  });

  const result = await response.json();
  if (!result.result || result.result === '0x') {
    throw new Error('Empty V2 response');
  }

  const hex = result.result.slice(2);
  const usdcHex = hex.slice(192, 256);
  const usdcAmount = Number(BigInt('0x' + usdcHex));
  const price = usdcAmount / 1e6;

  if (price <= 0) throw new Error('Invalid V2 price');
  return price;
}

/**
 * Fetch RON/USDC price with cascade: V3 → V2 → CoinGecko.
 */
async function fetchRonPrice(): Promise<number> {
  // 1. Katana V3 (matches Ronin Wallet swap price)
  try {
    const price = await fetchRonPriceV3();
    console.log(`RON price from Katana V3: $${price}`);
    return price;
  } catch (e) {
    console.warn('Katana V3 price failed:', e);
  }

  // 2. Katana V2 (fallback)
  try {
    const price = await fetchRonPriceV2();
    console.log(`RON price from Katana V2: $${price}`);
    return price;
  } catch (e) {
    console.warn('Katana V2 price failed:', e);
  }

  // 3. CoinGecko (last resort)
  try {
    const res = await fetch(
      'https://api.coingecko.com/api/v3/simple/price?ids=ronin&vs_currencies=usd',
      { headers: { 'Accept': 'application/json' } }
    );
    const data = await res.json();
    const price = data?.ronin?.usd;
    if (price && price > 0) {
      console.log(`RON price from CoinGecko: $${price}`);
      return price;
    }
  } catch (e) {
    console.error('CoinGecko price failed:', e);
  }

  throw new Error('Could not fetch RON price from any source');
}

/**
 * Call hedge-swap edge function for swap operations.
 */
async function callHedgeSwap(action: 'hedge' | 'unhedge', betId: string): Promise<{ success: boolean; error?: string }> {
  try {
    const url = `${Deno.env.get('SUPABASE_URL')}/functions/v1/hedge-swap`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
      },
      body: JSON.stringify({ action, bet_id: betId }),
    });
    const data = await res.json();
    return data;
  } catch (e) {
    console.error(`callHedgeSwap(${action}, ${betId}) failed:`, e);
    return { success: false, error: String(e) };
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 1. Fetch current RON/USDC price
    const price = await fetchRonPrice();
    console.log(`RON/USDC price: $${price}`);

    // 2. Record price snapshot
    const { error: insertErr } = await supabase
      .from('prediction_price_snapshots')
      .insert({ ron_usdc_price: price, source: 'katana' });

    if (insertErr) console.error('Error inserting price snapshot:', insertErr);

    // 3. Batch settle: una sola llamada SQL para todas las bets que alcanzaron target
    const errors: string[] = [];
    let settledCount = 0;
    let unhedgedCount = 0;

    const { data: settleResult, error: settleErr } = await supabase.rpc(
      'settle_all_prediction_bets',
      { p_current_price: price }
    );

    if (settleErr) {
      console.error('Error in batch settle:', settleErr);
      errors.push(`batch_settle: ${settleErr.message}`);
    } else if (settleResult?.success) {
      settledCount = settleResult.settled_count;
      console.log(`Batch settled ${settledCount} bets`);

      // Unhedge DOWN bets que lo necesitan (requiere llamadas externas individuales)
      for (const bet of (settleResult.settled_bets || [])) {
        if (bet.needs_unhedge) {
          const swapResult = await callHedgeSwap('unhedge', bet.bet_id);
          if (swapResult.success) {
            unhedgedCount++;
            console.log(`Unhedged bet ${bet.bet_id}`);
          } else {
            errors.push(`unhedge:${bet.bet_id}: ${swapResult.error}`);
          }
        }
      }
    }

    // 4. Safety net: retry pending/failed hedges via hedge-swap function
    let hedgeRetryCount = 0;
    const { data: pendingHedges } = await supabase
      .from('prediction_bets')
      .select('id')
      .eq('status', 'active')
      .eq('direction', 'down')
      .in('hedge_status', ['pending', 'failed']);

    for (const bet of (pendingHedges || [])) {
      const result = await callHedgeSwap('hedge', bet.id);
      if (result.success) {
        hedgeRetryCount++;
        console.log(`Retried hedge for bet ${bet.id}: success`);
      } else {
        errors.push(`hedge-retry:${bet.id}: ${result.error}`);
      }
    }

    // 5. Cleanup old price snapshots (keep last 7 days)
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    await supabase
      .from('prediction_price_snapshots')
      .delete()
      .lt('recorded_at', cutoff);

    return new Response(
      JSON.stringify({
        success: true,
        price,
        settled: settledCount,
        unhedged: unhedgedCount,
        hedge_retries: hedgeRetryCount,
        errors: errors.length > 0 ? errors : undefined,
        timestamp: new Date().toISOString(),
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('Prediction worker error:', message);
    return new Response(
      JSON.stringify({ success: false, error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
