import { ref, computed } from 'vue';

// Ronin chain config
const RONIN_CHAIN_ID = '0x7e4'; // 2020 in hex (Ronin Mainnet)
const RONIN_CHAIN_CONFIG = {
  chainId: RONIN_CHAIN_ID,
  chainName: 'Ronin',
  nativeCurrency: {
    name: 'RON',
    symbol: 'RON',
    decimals: 18,
  },
  rpcUrls: ['https://api.roninchain.com/rpc'],
  blockExplorerUrls: ['https://app.roninchain.com'],
};

// Game wallet address - where RON payments are sent
const GAME_WALLET_ADDRESS = import.meta.env.VITE_GAME_WALLET_ADDRESS || '';

// Global state (shared across all composable instances)
const isInstalled = ref(false);
const isConnecting = ref(false);
const isConnected = ref(false);
const account = ref<string | null>(null);
const chainId = ref<string | null>(null);
const error = ref<string | null>(null);

// Check if Ronin wallet is installed
function checkInstalled(): boolean {
  const installed = typeof window !== 'undefined' && !!(window as any).ronin?.provider;
  isInstalled.value = installed;
  return installed;
}

// Initialize on load
if (typeof window !== 'undefined') {
  checkInstalled();

  // Listen for account changes
  const provider = (window as any).ronin?.provider;
  if (provider) {
    provider.on('accountsChanged', (accounts: string[]) => {
      if (accounts.length === 0) {
        account.value = null;
        isConnected.value = false;
      } else {
        account.value = accounts[0];
        isConnected.value = true;
      }
    });

    provider.on('chainChanged', (newChainId: string) => {
      chainId.value = newChainId;
    });
  }
}

export function useRoninWallet() {
  const isCorrectChain = computed(() => chainId.value === RONIN_CHAIN_ID);

  const shortAddress = computed(() => {
    if (!account.value) return null;
    return `${account.value.slice(0, 6)}...${account.value.slice(-4)}`;
  });

  async function connect(): Promise<boolean> {
    error.value = null;

    if (!checkInstalled()) {
      error.value = 'Ronin Wallet no está instalado';
      return false;
    }

    const provider = (window as any).ronin.provider;
    isConnecting.value = true;

    try {
      // Request account access
      const accounts = await provider.request({
        method: 'eth_requestAccounts',
      });

      if (accounts.length === 0) {
        error.value = 'No se pudo conectar a la wallet';
        return false;
      }

      account.value = accounts[0];
      isConnected.value = true;

      // Get current chain
      const currentChainId = await provider.request({
        method: 'eth_chainId',
      });
      chainId.value = currentChainId;

      // Switch to Ronin if needed
      if (currentChainId !== RONIN_CHAIN_ID) {
        await switchToRonin();
      }

      return true;
    } catch (e: any) {
      console.error('Error connecting to Ronin:', e);
      error.value = e.message || 'Error al conectar';
      return false;
    } finally {
      isConnecting.value = false;
    }
  }

  async function switchToRonin(): Promise<boolean> {
    if (!isInstalled.value) return false;

    const provider = (window as any).ronin.provider;

    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: RONIN_CHAIN_ID }],
      });
      chainId.value = RONIN_CHAIN_ID;
      return true;
    } catch (e: any) {
      // Chain not added, try to add it
      if (e.code === 4902) {
        try {
          await provider.request({
            method: 'wallet_addEthereumChain',
            params: [RONIN_CHAIN_CONFIG],
          });
          chainId.value = RONIN_CHAIN_ID;
          return true;
        } catch (addError) {
          console.error('Error adding Ronin chain:', addError);
          error.value = 'No se pudo agregar la red Ronin';
          return false;
        }
      }
      console.error('Error switching to Ronin:', e);
      error.value = 'No se pudo cambiar a la red Ronin';
      return false;
    }
  }

  async function disconnect(): Promise<void> {
    account.value = null;
    isConnected.value = false;
    chainId.value = null;
    error.value = null;
  }

  async function sendRON(amountInRON: number): Promise<{ success: boolean; txHash?: string; error?: string }> {
    error.value = null;

    if (!isConnected.value || !account.value) {
      return { success: false, error: 'Wallet no conectada' };
    }

    if (!GAME_WALLET_ADDRESS) {
      return { success: false, error: 'Dirección de pago no configurada' };
    }

    if (!isCorrectChain.value) {
      const switched = await switchToRonin();
      if (!switched) {
        return { success: false, error: 'No se pudo cambiar a la red Ronin' };
      }
    }

    const provider = (window as any).ronin.provider;

    try {
      // Convert RON to wei (18 decimals)
      const amountInWei = BigInt(Math.floor(amountInRON * 1e18)).toString(16);

      const txHash = await provider.request({
        method: 'eth_sendTransaction',
        params: [{
          from: account.value,
          to: GAME_WALLET_ADDRESS,
          value: '0x' + amountInWei,
        }],
      });

      return { success: true, txHash };
    } catch (e: any) {
      console.error('Error sending RON:', e);

      // User rejected
      if (e.code === 4001) {
        return { success: false, error: 'Transacción cancelada por el usuario' };
      }

      return { success: false, error: e.message || 'Error al enviar RON' };
    }
  }

  async function waitForTransaction(txHash: string, maxAttempts = 30): Promise<{ confirmed: boolean; error?: string }> {
    if (!isInstalled.value) {
      return { confirmed: false, error: 'Wallet no instalada' };
    }

    const provider = (window as any).ronin.provider;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        const receipt = await provider.request({
          method: 'eth_getTransactionReceipt',
          params: [txHash],
        });

        if (receipt) {
          // status: '0x1' = success, '0x0' = failed
          if (receipt.status === '0x1') {
            return { confirmed: true };
          } else {
            return { confirmed: false, error: 'Transacción fallida' };
          }
        }
      } catch (e) {
        console.warn('Error checking transaction:', e);
      }

      // Wait 2 seconds before next attempt
      await new Promise(resolve => setTimeout(resolve, 2000));
    }

    return { confirmed: false, error: 'Timeout esperando confirmación' };
  }

  function openInstallPage() {
    window.open('https://wallet.roninchain.com/', '_blank');
  }

  return {
    // State
    isInstalled,
    isConnecting,
    isConnected,
    account,
    shortAddress,
    chainId,
    isCorrectChain,
    error,
    gameWalletAddress: GAME_WALLET_ADDRESS,

    // Actions
    checkInstalled,
    connect,
    disconnect,
    switchToRonin,
    sendRON,
    waitForTransaction,
    openInstallPage,
  };
}
