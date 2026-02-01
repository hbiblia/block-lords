// Supabase Edge Function para procesar retiros de RON automáticamente
// Se ejecuta via cron cada X minutos

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { ethers } from 'https://esm.sh/ethers@6.9.0';

// Configuración Ronin
const RONIN_RPC = 'https://api.roninchain.com/rpc';
const RONIN_CHAIN_ID = 2020;

// Headers CORS
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
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
    // Verificar autenticación con Service Role Key
    const authHeader = req.headers.get('Authorization');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!authHeader || !supabaseKey || !authHeader.includes(supabaseKey)) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Obtener configuración
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const hotWalletPrivateKey = Deno.env.get('HOT_WALLET_PRIVATE_KEY');

    if (!hotWalletPrivateKey) {
      throw new Error('HOT_WALLET_PRIVATE_KEY not configured');
    }

    // Crear cliente Supabase con service role
    const supabase = createClient(supabaseUrl, supabaseKey);

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

    const results: { id: string; success: boolean; txHash?: string; error?: string }[] = [];
    let totalProcessed = 0;
    let totalFailed = 0;

    // Procesar cada retiro
    for (const withdrawal of pendingWithdrawals as WithdrawalRecord[]) {
      console.log(`Processing withdrawal ${withdrawal.id} for ${withdrawal.username}`);
      console.log(`  Amount: ${withdrawal.net_amount} RON to ${withdrawal.wallet_address}`);

      try {
        // Verificar que tenemos suficiente balance
        const amountWei = ethers.parseEther(withdrawal.net_amount.toString());

        // Estimar gas
        const gasPrice = await provider.getFeeData();
        const estimatedGas = 21000n; // Transfer simple
        const gasCost = estimatedGas * (gasPrice.gasPrice || 0n);
        const totalNeeded = amountWei + gasCost;

        const currentBalance = await provider.getBalance(wallet.address);

        if (currentBalance < totalNeeded) {
          console.log(`  Insufficient balance for withdrawal ${withdrawal.id}`);

          // Marcar como fallido
          await supabase.rpc('admin_fail_withdrawal', {
            p_withdrawal_id: withdrawal.id,
            p_error_message: 'Insufficient hot wallet balance',
          });

          results.push({ id: withdrawal.id, success: false, error: 'Insufficient balance' });
          totalFailed++;
          continue;
        }

        // Marcar como "processing"
        const { data: startResult } = await supabase.rpc('admin_start_processing', {
          p_withdrawal_id: withdrawal.id,
        });

        if (!startResult?.success) {
          console.log(`  Could not start processing: ${startResult?.error}`);
          results.push({ id: withdrawal.id, success: false, error: startResult?.error });
          totalFailed++;
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

          // Marcar como completado
          await supabase.rpc('admin_complete_withdrawal', {
            p_withdrawal_id: withdrawal.id,
            p_tx_hash: tx.hash,
          });

          results.push({ id: withdrawal.id, success: true, txHash: tx.hash });
          totalProcessed++;
        } else {
          console.log(`  Transaction failed`);

          await supabase.rpc('admin_fail_withdrawal', {
            p_withdrawal_id: withdrawal.id,
            p_error_message: 'Transaction reverted',
          });

          results.push({ id: withdrawal.id, success: false, error: 'Transaction reverted' });
          totalFailed++;
        }

      } catch (txError: any) {
        console.error(`  Error processing withdrawal ${withdrawal.id}:`, txError);

        // Marcar como fallido
        await supabase.rpc('admin_fail_withdrawal', {
          p_withdrawal_id: withdrawal.id,
          p_error_message: txError.message?.substring(0, 200) || 'Unknown error',
        });

        results.push({ id: withdrawal.id, success: false, error: txError.message });
        totalFailed++;
      }

      // Pequeña pausa entre transacciones para evitar nonce issues
      await new Promise(resolve => setTimeout(resolve, 2000));
    }

    // Obtener nuevo balance
    const finalBalance = await provider.getBalance(wallet.address);
    const finalBalanceRON = parseFloat(ethers.formatEther(finalBalance));

    return new Response(
      JSON.stringify({
        success: true,
        processed: totalProcessed,
        failed: totalFailed,
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
