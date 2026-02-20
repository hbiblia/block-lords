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
const WETH = '0xc99a6a985ed2cac1ef41640596c5a5f9f4e19ef5';
const GET_AMOUNTS_OUT_SELECTOR = '0xd06ca61f';

// === RON PRICE FUNCTIONS ===

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

// === WETH PRICE FUNCTIONS ===

function pad256(hex: string): string {
  return hex.replace('0x', '').padStart(64, '0');
}

/**
 * Fetch WETH/USD price from Katana V2 via getAmountsOut (1 WETH → USDC).
 * Tries direct WETH→USDC first, then WETH→WRON→USDC.
 */
async function fetchWethPriceV2(): Promise<number> {
  const oneWeth = BigInt('1000000000000000000');
  const amountIn = pad256(oneWeth.toString(16));

  // Try direct WETH → USDC
  const wethPadded = pad256(WETH.slice(2));
  const usdcPadded = pad256(USDC.slice(2));

  const data2hop = GET_AMOUNTS_OUT_SELECTOR + amountIn +
    pad256('40') + // offset to path array
    pad256('2') +  // path length
    wethPadded + usdcPadded;

  try {
    const response = await fetch(RONIN_RPC, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0', method: 'eth_call',
        params: [{ to: KATANA_V2_ROUTER, data: data2hop }, 'latest'], id: 1,
      }),
    });

    const result = await response.json();
    if (result.result && result.result !== '0x' && result.result.length > 130) {
      const hex = result.result.slice(2);
      const usdcHex = hex.slice(192, 256);
      const usdcAmount = Number(BigInt('0x' + usdcHex));
      const price = usdcAmount / 1e6;
      if (price > 0) {
        console.log(`WETH price from Katana V2 direct: $${price}`);
        return price;
      }
    }
  } catch (e) {
    console.warn('WETH V2 direct failed:', e);
  }

  // Fallback: WETH → WRON → USDC (3-hop)
  const wronPadded = pad256(WRON.slice(2));
  const data3hop = GET_AMOUNTS_OUT_SELECTOR + amountIn +
    pad256('40') + // offset
    pad256('3') +  // path length
    wethPadded + wronPadded + usdcPadded;

  const response = await fetch(RONIN_RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0', method: 'eth_call',
      params: [{ to: KATANA_V2_ROUTER, data: data3hop }, 'latest'], id: 1,
    }),
  });

  const result = await response.json();
  if (!result.result || result.result === '0x') {
    throw new Error('Empty V2 WETH 3-hop response');
  }

  const hex = result.result.slice(2);
  // For 3-hop: offset(64) + length(64) + amount0(64) + amount1(64) + amount2(64)
  const usdcHex = hex.slice(256, 320);
  const usdcAmount = Number(BigInt('0x' + usdcHex));
  const price = usdcAmount / 1e6;

  if (price <= 0) throw new Error('Invalid WETH V2 3-hop price');
  console.log(`WETH price from Katana V2 via WRON: $${price}`);
  return price;
}

/**
 * Fetch WETH/USD price with cascade: Katana V2 → CoinGecko.
 */
async function fetchWethPrice(): Promise<number> {
  // 1. Katana V2 (direct or via WRON)
  try {
    return await fetchWethPriceV2();
  } catch (e) {
    console.warn('Katana V2 WETH price failed:', e);
  }

  // 2. CoinGecko (WETH on Ronin = bridged ETH)
  try {
    const res = await fetch(
      'https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd',
      { headers: { 'Accept': 'application/json' } }
    );
    const data = await res.json();
    const price = data?.ethereum?.usd;
    if (price && price > 0) {
      console.log(`WETH price from CoinGecko: $${price}`);
      return price;
    }
  } catch (e) {
    console.error('CoinGecko WETH price failed:', e);
  }

  throw new Error('Could not fetch WETH price from any source');
}

/**
 * Call hedge-swap edge function for swap operations.
 */
async function callHedgeSwap(action: 'hedge' | 'unhedge', betId: string): Promise<{ success: boolean; error?: string; ron_received?: string; tx_hash?: string }> {
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

    // 1. Fetch current prices (RON + WETH)
    const price = await fetchRonPrice();
    console.log(`RON/USDC price: $${price}`);

    let wethPrice: number | null = null;
    try {
      wethPrice = await fetchWethPrice();
      console.log(`WETH/USD price: $${wethPrice}`);
    } catch (e) {
      console.warn('WETH price fetch failed (UP bets unaffected this cycle):', e);
    }

    // 2. Record price snapshot (with WETH price if available)
    const { error: insertErr } = await supabase
      .from('prediction_price_snapshots')
      .insert({
        ron_usdc_price: price,
        weth_usd_price: wethPrice,
        source: 'katana',
      });

    if (insertErr) console.error('Error inserting price snapshot:', insertErr);

    // 3. Batch settle: pass both prices
    const errors: string[] = [];
    let settledCount = 0;
    let unhedgedCount = 0;

    const { data: settleResult, error: settleErr } = await supabase.rpc(
      'settle_all_prediction_bets',
      { p_current_price: price, p_current_weth_price: wethPrice }
    );

    if (settleErr) {
      console.error('Error in batch settle:', settleErr);
      errors.push(`batch_settle: ${settleErr.message}`);
    } else if (settleResult?.success) {
      settledCount = settleResult.settled_count;
      console.log(`Batch settled ${settledCount} bets`);

      // Process settled bets that need unhedge
      for (const bet of (settleResult.settled_bets || [])) {
        if (bet.needs_unhedge) {
          const swapResult = await callHedgeSwap('unhedge', bet.bet_id);
          if (swapResult.success) {
            if (bet.direction === 'up' && swapResult.ron_received) {
              // UP bets: finalize with actual RON received from WETH→RON swap
              const { error: settleUpErr } = await supabase.rpc(
                'settle_up_bet_with_swap',
                {
                  p_bet_id: bet.bet_id,
                  p_ron_received: parseFloat(swapResult.ron_received),
                  p_unhedge_tx_hash: swapResult.tx_hash || '',
                }
              );
              if (settleUpErr) {
                errors.push(`settle_up:${bet.bet_id}: ${settleUpErr.message}`);
              } else {
                unhedgedCount++;
                console.log(`Settled UP bet ${bet.bet_id} with ${swapResult.ron_received} RON received`);
              }
            } else {
              // DOWN bets: unhedge only (payout already done in SQL)
              unhedgedCount++;
              console.log(`Unhedged DOWN bet ${bet.bet_id}`);
            }
          } else {
            errors.push(`unhedge:${bet.bet_id}: ${swapResult.error}`);
          }
        }
      }
    }

    // 4. Safety net: retry pending/failed hedges for BOTH directions
    let hedgeRetryCount = 0;
    const { data: pendingHedges } = await supabase
      .from('prediction_bets')
      .select('id, direction')
      .eq('status', 'active')
      .in('hedge_status', ['pending', 'failed']);

    for (const bet of (pendingHedges || [])) {
      const result = await callHedgeSwap('hedge', bet.id);
      if (result.success) {
        hedgeRetryCount++;
        console.log(`Retried hedge for ${bet.direction} bet ${bet.id}: success`);
      } else {
        errors.push(`hedge-retry:${bet.id}: ${result.error}`);
      }
    }

    // 4b. Retry pending_unhedge UP bets (crash recovery)
    const { data: pendingUnhedge } = await supabase
      .from('prediction_bets')
      .select('id')
      .eq('status', 'pending_unhedge')
      .eq('direction', 'up');

    for (const bet of (pendingUnhedge || [])) {
      const swapResult = await callHedgeSwap('unhedge', bet.id);
      if (swapResult.success && swapResult.ron_received) {
        const { error: settleUpErr } = await supabase.rpc(
          'settle_up_bet_with_swap',
          {
            p_bet_id: bet.id,
            p_ron_received: parseFloat(swapResult.ron_received),
            p_unhedge_tx_hash: swapResult.tx_hash || '',
          }
        );
        if (!settleUpErr) {
          console.log(`Recovered pending_unhedge bet ${bet.id}`);
        } else {
          errors.push(`recover_unhedge:${bet.id}: ${settleUpErr.message}`);
        }
      } else {
        errors.push(`recover_unhedge:${bet.id}: ${swapResult.error}`);
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
        weth_price: wethPrice,
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
