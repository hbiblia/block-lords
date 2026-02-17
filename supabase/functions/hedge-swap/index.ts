import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// === KATANA DEX CONSTANTS ===

const RONIN_RPC = 'https://api.roninchain.com/rpc';
const KATANA_ROUTER = '0x7D0556D55ca1a92708681E2e231733EBd922597D';
const WRON_ADDR = '0xe514d9DEB7966c8BE0ca922de8a064264eA6bcd4';
const USDC_ADDR = '0x0B7007c13325C48911F73A2daD5FA5dcBf808aDc';

const MAX_SLIPPAGE_BPS = 300n; // 3%
const BPS = 10000n;

const SEL = {
  deposit: '0xd0e30db0',
  withdraw: '0x2e1a7d4d',
  approve: '0x095ea7b3',
  allowance: '0xdd62ed3e',
  balanceOf: '0x70a08231',
  swapExactTokensForTokens: '0x38ed1739',
  getAmountsOut: '0xd06ca61f',
};

// === HELPERS ===

function pad256(hex: string): string {
  return hex.replace('0x', '').padStart(64, '0');
}
function uint256(n: bigint): string {
  return pad256(n.toString(16));
}
function addr(a: string): string {
  return pad256(a.toLowerCase().replace('0x', ''));
}

async function rpcCall(to: string, data: string): Promise<string> {
  const res = await fetch(RONIN_RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0', method: 'eth_call',
      params: [{ to, data }, 'latest'], id: 1,
    }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`RPC error: ${json.error.message}`);
  return json.result;
}

async function sendTx(params: {
  to: string; data: string; value?: bigint; gasLimit?: bigint;
}): Promise<string> {
  const key = Deno.env.get('HOT_WALLET_PRIVATE_KEY');
  if (!key) throw new Error('HOT_WALLET_PRIVATE_KEY not set');

  const { ethers } = await import('https://esm.sh/ethers@6');
  const provider = new ethers.JsonRpcProvider(RONIN_RPC);
  const wallet = new ethers.Wallet(key, provider);

  const tx = await wallet.sendTransaction({
    to: params.to,
    data: params.data,
    value: params.value ?? 0n,
    gasLimit: params.gasLimit ?? 500000n,
  });
  const receipt = await tx.wait();
  if (!receipt || receipt.status === 0) throw new Error(`TX failed: ${tx.hash}`);
  return receipt.hash;
}

async function getWalletAddress(): Promise<string> {
  const key = Deno.env.get('HOT_WALLET_PRIVATE_KEY');
  if (!key) throw new Error('HOT_WALLET_PRIVATE_KEY not set');
  const { ethers } = await import('https://esm.sh/ethers@6');
  return new ethers.Wallet(key).address;
}

async function getAmountsOut(amountIn: bigint, path: string[]): Promise<bigint[]> {
  const pathOffset = uint256(64n);
  const pathLength = uint256(BigInt(path.length));
  const pathEncoded = path.map(p => addr(p)).join('');
  const data = SEL.getAmountsOut + uint256(amountIn) + pathOffset + pathLength + pathEncoded;
  const result = await rpcCall(KATANA_ROUTER, data);
  const hex = result.slice(2);
  const len = Number(BigInt('0x' + hex.slice(64, 128)));
  const amounts: bigint[] = [];
  for (let i = 0; i < len; i++) {
    amounts.push(BigInt('0x' + hex.slice(128 + i * 64, 192 + i * 64)));
  }
  return amounts;
}

async function getBalanceOf(token: string, account: string): Promise<bigint> {
  const data = SEL.balanceOf + addr(account);
  const result = await rpcCall(token, data);
  return BigInt(result);
}

async function getAllowance(token: string, owner: string, spender: string): Promise<bigint> {
  const data = SEL.allowance + addr(owner) + addr(spender);
  const result = await rpcCall(token, data);
  return BigInt(result);
}

// === SWAP FUNCTIONS ===

async function swapRONtoUSDC(ronAmount: string): Promise<{ usdcReceived: string; txHash: string }> {
  const { ethers } = await import('https://esm.sh/ethers@6');
  const walletAddr = await getWalletAddress();
  const ronWei = ethers.parseEther(ronAmount);

  console.log(`[HEDGE] Swapping ${ronAmount} RON → USDC`);

  // 1. Wrap RON → WRON
  await sendTx({ to: WRON_ADDR, data: SEL.deposit, value: ronWei, gasLimit: 100000n });

  // 2. Approve WRON for router if needed
  const allowance = await getAllowance(WRON_ADDR, walletAddr, KATANA_ROUTER);
  if (allowance < ronWei) {
    const maxUint = (1n << 256n) - 1n;
    await sendTx({ to: WRON_ADDR, data: SEL.approve + addr(KATANA_ROUTER) + uint256(maxUint), gasLimit: 100000n });
  }

  // 3. Min output with slippage
  const expected = await getAmountsOut(ronWei, [WRON_ADDR, USDC_ADDR]);
  const minOut = expected[1] * (BPS - MAX_SLIPPAGE_BPS) / BPS;

  // 4. USDC balance before
  const usdcBefore = await getBalanceOf(USDC_ADDR, walletAddr);

  // 5. Swap WRON → USDC
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 300);
  const swapData = SEL.swapExactTokensForTokens +
    uint256(ronWei) + uint256(minOut) + uint256(160n) +
    addr(walletAddr) + uint256(deadline) +
    uint256(2n) + addr(WRON_ADDR) + addr(USDC_ADDR);

  const txHash = await sendTx({ to: KATANA_ROUTER, data: swapData, gasLimit: 300000n });

  // 6. USDC received
  const usdcAfter = await getBalanceOf(USDC_ADDR, walletAddr);
  const usdcReceived = (usdcAfter - usdcBefore).toString();

  console.log(`[HEDGE] Done: ${ronAmount} RON → ${Number(usdcReceived) / 1e6} USDC (${txHash})`);
  return { usdcReceived, txHash };
}

async function swapUSDCtoRON(usdcRaw: string): Promise<{ ronReceived: string; txHash: string }> {
  const { ethers } = await import('https://esm.sh/ethers@6');
  const walletAddr = await getWalletAddress();
  const usdcAmount = BigInt(usdcRaw);

  console.log(`[UNHEDGE] Swapping ${Number(usdcAmount) / 1e6} USDC → RON`);

  // 1. Approve USDC for router if needed
  const allowance = await getAllowance(USDC_ADDR, walletAddr, KATANA_ROUTER);
  if (allowance < usdcAmount) {
    const maxUint = (1n << 256n) - 1n;
    await sendTx({ to: USDC_ADDR, data: SEL.approve + addr(KATANA_ROUTER) + uint256(maxUint), gasLimit: 100000n });
  }

  // 2. Min output with slippage
  const expected = await getAmountsOut(usdcAmount, [USDC_ADDR, WRON_ADDR]);
  const minOut = expected[1] * (BPS - MAX_SLIPPAGE_BPS) / BPS;

  // 3. WRON balance before
  const wronBefore = await getBalanceOf(WRON_ADDR, walletAddr);

  // 4. Swap USDC → WRON
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 300);
  const swapData = SEL.swapExactTokensForTokens +
    uint256(usdcAmount) + uint256(minOut) + uint256(160n) +
    addr(walletAddr) + uint256(deadline) +
    uint256(2n) + addr(USDC_ADDR) + addr(WRON_ADDR);

  const txHash = await sendTx({ to: KATANA_ROUTER, data: swapData, gasLimit: 300000n });

  // 5. Unwrap WRON → RON
  const wronAfter = await getBalanceOf(WRON_ADDR, walletAddr);
  const wronReceived = wronAfter - wronBefore;
  if (wronReceived > 0n) {
    await sendTx({ to: WRON_ADDR, data: SEL.withdraw + uint256(wronReceived), gasLimit: 100000n });
  }

  const ronReceived = ethers.formatEther(wronReceived);
  console.log(`[UNHEDGE] Done: USDC → ${ronReceived} RON (${txHash})`);
  return { ronReceived, txHash };
}

// === EDGE FUNCTION ===

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { action, bet_id } = await req.json();

    if (!action || !bet_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing action or bet_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const { data: bet, error: betErr } = await supabase
      .from('prediction_bets')
      .select('id, direction, bet_amount_ron, hedge_status, hedge_usdc_amount')
      .eq('id', bet_id)
      .single();

    if (betErr || !bet) {
      return new Response(
        JSON.stringify({ success: false, error: 'Bet not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (bet.direction !== 'down') {
      return new Response(
        JSON.stringify({ success: true, message: 'UP bet, no hedge needed' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // === HEDGE: RON → USDC ===
    if (action === 'hedge') {
      if (bet.hedge_status !== 'pending' && bet.hedge_status !== 'failed') {
        return new Response(
          JSON.stringify({ success: true, message: `Already ${bet.hedge_status}` }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      try {
        const result = await swapRONtoUSDC(bet.bet_amount_ron.toString());

        await supabase
          .from('prediction_bets')
          .update({
            hedge_status: 'hedged',
            hedge_usdc_amount: Number(result.usdcReceived) / 1e6,
            hedge_tx_hash: result.txHash,
          })
          .eq('id', bet_id);

        return new Response(
          JSON.stringify({
            success: true,
            usdc_received: Number(result.usdcReceived) / 1e6,
            tx_hash: result.txHash,
          }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      } catch (swapErr) {
        console.error(`[HEDGE] Swap failed for bet ${bet_id}:`, swapErr);
        await supabase
          .from('prediction_bets')
          .update({ hedge_status: 'failed' })
          .eq('id', bet_id);

        return new Response(
          JSON.stringify({ success: false, error: `Swap failed: ${swapErr}` }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }

    // === UNHEDGE: USDC → RON ===
    if (action === 'unhedge') {
      if (bet.hedge_status !== 'hedged' || !bet.hedge_usdc_amount) {
        return new Response(
          JSON.stringify({ success: true, message: 'Not hedged, nothing to unhedge' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      const usdcRaw = Math.round(Number(bet.hedge_usdc_amount) * 1e6).toString();
      const result = await swapUSDCtoRON(usdcRaw);

      await supabase
        .from('prediction_bets')
        .update({ unhedge_tx_hash: result.txHash })
        .eq('id', bet_id);

      return new Response(
        JSON.stringify({
          success: true,
          ron_received: result.ronReceived,
          tx_hash: result.txHash,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    return new Response(
      JSON.stringify({ success: false, error: 'Invalid action. Use hedge or unhedge' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('Hedge-swap error:', message);
    return new Response(
      JSON.stringify({ success: false, error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
