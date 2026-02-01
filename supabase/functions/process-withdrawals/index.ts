// Supabase Edge Function para procesar retiros de RON automáticamente
// Se ejecuta via cron cada minuto
// IMPORTANTE: Deploy con --no-verify-jwt

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { ethers } from 'https://esm.sh/ethers@6.9.0';

// Configuración Ronin
const RONIN_RPC = 'https://api.roninchain.com/rpc';
const RONIN_CHAIN_ID = 2020;

// Cuantos retiros procesar por llamada (max para evitar timeout de 30s)
const BATCH_SIZE = 5;

// Headers CORS
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface WithdrawalRecord {
  id: string;
  player_id: string;
  username: string;
  email: string;
  amount: number;
  fee: number;
  net_amount: number;
  wallet_address: string;
  status: string;
  created_at: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Obtener configuración
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const hotWalletPrivateKey = Deno.env.get('HOT_WALLET_PRIVATE_KEY');

    // Verificar autorización usando service role key
    const serviceRoleKey = supabaseServiceKey;
    const authHeader = req.headers.get('authorization');
    const providedKey = authHeader?.replace('Bearer ', '');

    if (providedKey !== serviceRoleKey) {
      console.log('Invalid or missing authorization');
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('Processing withdrawals request received');

    if (!hotWalletPrivateKey) {
      throw new Error('HOT_WALLET_PRIVATE_KEY not configured');
    }

    // Crear cliente Supabase con service role
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Conectar a Ronin
    const provider = new ethers.JsonRpcProvider(RONIN_RPC, RONIN_CHAIN_ID);
    const wallet = new ethers.Wallet(hotWalletPrivateKey, provider);

    console.log(`Hot wallet address: ${wallet.address}`);

    // Verificar balance del hot wallet
    const hotWalletBalance = await provider.getBalance(wallet.address);
    const hotWalletBalanceRON = parseFloat(ethers.formatEther(hotWalletBalance));
    console.log(`Hot wallet balance: ${hotWalletBalanceRON} RON`);

    // Obtener retiros pendientes
    const { data: pendingWithdrawals, error: fetchError } = await supabase
      .rpc('admin_get_pending_withdrawals');

    if (fetchError) {
      throw new Error(`Error fetching withdrawals: ${fetchError.message}`);
    }

    if (!pendingWithdrawals || pendingWithdrawals.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: 'No pending withdrawals', processed: 0 }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Found ${pendingWithdrawals.length} pending withdrawals`);

    // Procesar batch de retiros
    const batch = (pendingWithdrawals as WithdrawalRecord[]).slice(0, BATCH_SIZE);
    console.log(`Processing batch of ${batch.length} withdrawals`);

    const results: Array<{ id: string; success: boolean; tx_hash?: string; error?: string }> = [];
    let processedCount = 0;
    let failedCount = 0;
    let currentBalance = await provider.getBalance(wallet.address);

    // Estimar gas una vez
    const gasPrice = await provider.getFeeData();
    const estimatedGas = 21000n;
    const gasCost = estimatedGas * (gasPrice.gasPrice || 0n);

    for (const withdrawal of batch) {
      console.log(`Processing withdrawal ${withdrawal.id} for ${withdrawal.username}`);
      console.log(`  Amount: ${withdrawal.net_amount} RON to ${withdrawal.wallet_address}`);

      try {
        const amountWei = ethers.parseEther(withdrawal.net_amount.toString());
        const totalNeeded = amountWei + gasCost;

        if (currentBalance < totalNeeded) {
          console.log(`  Insufficient balance for withdrawal ${withdrawal.id}`);
          await supabase.rpc('admin_fail_withdrawal', {
            p_withdrawal_id: withdrawal.id,
            p_error_message: 'Insufficient hot wallet balance',
          });
          results.push({ id: withdrawal.id, success: false, error: 'Insufficient balance' });
          failedCount++;
          continue;
        }

        // Marcar como processing
        const { data: startResult } = await supabase.rpc('admin_start_processing', {
          p_withdrawal_id: withdrawal.id,
        });

        if (!startResult?.success) {
          console.log(`  Could not start processing: ${startResult?.error}`);
          results.push({ id: withdrawal.id, success: false, error: startResult?.error });
          failedCount++;
          continue;
        }

        // Enviar transacción
        console.log(`  Sending ${withdrawal.net_amount} RON...`);
        const tx = await wallet.sendTransaction({
          to: withdrawal.wallet_address,
          value: amountWei,
          gasLimit: estimatedGas,
        });

        console.log(`  Transaction sent: ${tx.hash}`);

        // Esperar confirmación
        const receipt = await tx.wait(1);

        if (receipt?.status === 1) {
          console.log(`  Transaction confirmed!`);
          await supabase.rpc('admin_complete_withdrawal', {
            p_withdrawal_id: withdrawal.id,
            p_tx_hash: tx.hash,
          });
          results.push({ id: withdrawal.id, success: true, tx_hash: tx.hash });
          processedCount++;
          currentBalance = currentBalance - amountWei - gasCost;
        } else {
          console.log(`  Transaction failed`);
          await supabase.rpc('admin_fail_withdrawal', {
            p_withdrawal_id: withdrawal.id,
            p_error_message: 'Transaction reverted',
          });
          results.push({ id: withdrawal.id, success: false, error: 'Transaction reverted' });
          failedCount++;
        }

      } catch (txError: any) {
        console.error(`  Error processing withdrawal ${withdrawal.id}:`, txError);
        await supabase.rpc('admin_fail_withdrawal', {
          p_withdrawal_id: withdrawal.id,
          p_error_message: txError.message?.substring(0, 200) || 'Unknown error',
        });
        results.push({ id: withdrawal.id, success: false, error: txError.message });
        failedCount++;
      }
    }

    // Obtener balance final
    const finalBalance = await provider.getBalance(wallet.address);
    const finalBalanceRON = parseFloat(ethers.formatEther(finalBalance));

    return new Response(
      JSON.stringify({
        success: true,
        processed: processedCount,
        failed: failedCount,
        pending_count: pendingWithdrawals.length - batch.length,
        hotWalletBalance: finalBalanceRON,
        results,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error: any) {
    console.error('Error in process-withdrawals:', error);

    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
