// Supabase Edge Function to verify Ronin blockchain transactions
// Deno Deploy runtime

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RONIN_RPC_URL = "https://api.roninchain.com/rpc";
const GAME_WALLET_ADDRESS = Deno.env.get("GAME_WALLET_ADDRESS")?.toLowerCase() || "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface VerifyRequest {
  txHash: string;
  packageId: string;
  playerId: string;
  expectedAmount: number; // RON amount expected
}

interface RpcResponse {
  jsonrpc: string;
  id: number;
  result?: any;
  error?: { code: number; message: string };
}

async function getTransactionReceipt(txHash: string): Promise<any> {
  const response = await fetch(RONIN_RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "eth_getTransactionReceipt",
      params: [txHash],
      id: 1,
    }),
  });

  const data: RpcResponse = await response.json();

  if (data.error) {
    throw new Error(data.error.message);
  }

  return data.result;
}

async function getTransaction(txHash: string): Promise<any> {
  const response = await fetch(RONIN_RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "eth_getTransactionByHash",
      params: [txHash],
      id: 1,
    }),
  });

  const data: RpcResponse = await response.json();

  if (data.error) {
    throw new Error(data.error.message);
  }

  return data.result;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { txHash, packageId, playerId, expectedAmount }: VerifyRequest = await req.json();

    // Validate inputs
    if (!txHash || !packageId || !playerId) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Check if tx_hash already used
    const { data: existingPurchase } = await supabase
      .from("crypto_purchases")
      .select("id")
      .eq("tx_hash", txHash)
      .single();

    if (existingPurchase) {
      return new Response(
        JSON.stringify({ success: false, error: "Transaction already used" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get transaction receipt from Ronin
    const receipt = await getTransactionReceipt(txHash);

    if (!receipt) {
      return new Response(
        JSON.stringify({ success: false, error: "Transaction not found or pending" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Check if transaction succeeded
    if (receipt.status !== "0x1") {
      return new Response(
        JSON.stringify({ success: false, error: "Transaction failed on blockchain" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get full transaction to verify amount and recipient
    const tx = await getTransaction(txHash);

    if (!tx) {
      return new Response(
        JSON.stringify({ success: false, error: "Could not retrieve transaction details" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Verify recipient is our game wallet
    if (tx.to?.toLowerCase() !== GAME_WALLET_ADDRESS) {
      return new Response(
        JSON.stringify({ success: false, error: "Transaction recipient mismatch" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Verify amount (convert from hex wei to RON)
    const valueWei = BigInt(tx.value);
    const valueRon = Number(valueWei) / 1e18;

    // Allow 1% tolerance for gas variations
    const minExpected = expectedAmount * 0.99;
    if (valueRon < minExpected) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `Insufficient payment: expected ${expectedAmount} RON, received ${valueRon.toFixed(4)} RON`
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // All verifications passed - credit the crypto
    const { data: result, error: rpcError } = await supabase.rpc("buy_crypto_package", {
      p_player_id: playerId,
      p_package_id: packageId,
      p_tx_hash: txHash,
    });

    if (rpcError) {
      console.error("RPC error:", rpcError);
      return new Response(
        JSON.stringify({ success: false, error: "Failed to credit crypto" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        cryptoReceived: result?.crypto_received,
        txVerified: true
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message || "Internal error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
