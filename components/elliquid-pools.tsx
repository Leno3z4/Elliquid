"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  formatUnits,
  getAddress,
  isAddress,
  parseAbi,
  parseUnits,
  type Address,
  type Hash,
} from "viem";
import { useAccount, useChainId, usePublicClient, useSwitchChain, useWriteContract } from "wagmi";

const ELYSIUM_TESTNET_ID = 99801;
const PAGE_SIZE = 10;

const factoryAbi = parseAbi([
  "function owner() view returns (address)",
  "function paused() view returns (bool)",
  "function poolCount() view returns (uint256)",
  "function getPools(uint256 start, uint256 limit) view returns (address[] page)",
  "function createPool(address tokenA, address tokenB) returns (address pool)",
  "function tokenAllowed(address token) view returns (bool)",
  "function setTokenAllowed(address token, bool allowed)",
  "function setPaused(bool shouldPause)",
]);

const poolAbi = parseAbi([
  "function token0() view returns (address)",
  "function token1() view returns (address)",
  "function feeBps() view returns (uint16)",
  "function totalSupply() view returns (uint256)",
  "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint256 lastUpdated)",
  "function quoteExactInput(address tokenIn, uint256 amountIn) view returns (uint256 amountOut)",
  "function previewAddLiquidity(uint256 amount0Desired, uint256 amount1Desired) view returns (uint256 amount0, uint256 amount1, uint256 shares)",
  "function previewRemoveLiquidity(uint256 shares) view returns (uint256 amount0, uint256 amount1)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
]);

const routerAbi = parseAbi([
  "function previewAddLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired) view returns (uint256 amountA, uint256 amountB, uint256 shares)",
  "function getAmountsOut(uint256 amountIn, address[] path) view returns (uint256[] amounts)",
  "function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 minAmountA, uint256 minAmountB, uint256 minShares, address recipient, uint256 deadline) returns (uint256 amountA, uint256 amountB, uint256 shares)",
  "function removeLiquidity(address tokenA, address tokenB, uint256 shares, uint256 minAmountA, uint256 minAmountB, address recipient, uint256 deadline) returns (uint256 amountA, uint256 amountB)",
  "function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address recipient, uint256 deadline) returns (uint256[] amounts)",
]);

const erc20Abi = parseAbi([
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function approve(address spender, uint256 amount) returns (bool)",
]);

type PoolInfo = {
  address: Address;
  token0: Address;
  token1: Address;
  symbol0: string;
  symbol1: string;
  decimals0: number;
  decimals1: number;
  reserve0: bigint;
  reserve1: bigint;
  totalSupply: bigint;
  feeBps: number;
  metadataOk: boolean;
};

function shortAddress(value: string) {
  return value.slice(0, 6) + "…" + value.slice(-4);
}

function displayAmount(value: bigint, decimals: number) {
  const number = Number(formatUnits(value, decimals));
  if (!Number.isFinite(number)) return "—";
  return number.toLocaleString("en-US", { maximumFractionDigits: 5 });
}

function messageOf(error: unknown) {
  if (error instanceof Error) return error.message.replace(/^ContractFunctionExecutionError: /, "").slice(0, 240);
  return String(error).slice(0, 240);
}

async function mapInBatches<T, R>(
  items: readonly T[],
  batchSize: number,
  mapper: (item: T) => Promise<R>,
): Promise<R[]> {
  const result: R[] = [];
  for (let offset = 0; offset < items.length; offset += batchSize) {
    const batch = items.slice(offset, offset + batchSize);
    result.push(...await Promise.all(batch.map(mapper)));
  }
  return result;
}

export function ElliquidPools() {
  const factoryAddressRaw = process.env.NEXT_PUBLIC_ELLIQUID_POOL_FACTORY_ADDRESS?.trim() ?? "";
  const routerAddressRaw = process.env.NEXT_PUBLIC_ELLIQUID_ROUTER_ADDRESS?.trim() ?? "";
  const configured = isAddress(factoryAddressRaw) && isAddress(routerAddressRaw);
  const factoryAddress = configured ? getAddress(factoryAddressRaw) : undefined;
  const routerAddress = configured ? getAddress(routerAddressRaw) : undefined;

  const client = usePublicClient({ chainId: ELYSIUM_TESTNET_ID });
  const { address: wallet } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const { writeContractAsync, isPending } = useWriteContract();

  const [pools, setPools] = useState<PoolInfo[]>([]);
  const [nextStart, setNextStart] = useState(0);
  const [totalPools, setTotalPools] = useState<bigint>(0n);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [factoryOwner, setFactoryOwner] = useState<Address | null>(null);
  const [protocolPaused, setProtocolPaused] = useState<boolean | null>(null);
  const [selectedAddress, setSelectedAddress] = useState<string>("");
  const [swapQuote, setSwapQuote] = useState<{ output: string; minimum: string; symbol: string } | null>(null);
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [quoteLoading, setQuoteLoading] = useState(false);

  const [tokenAInput, setTokenAInput] = useState("");
  const [tokenBInput, setTokenBInput] = useState("");
  const [amount0Input, setAmount0Input] = useState("");
  const [amount1Input, setAmount1Input] = useState("");
  const [swapAmountInput, setSwapAmountInput] = useState("");
  const [swapTokenIn, setSwapTokenIn] = useState<"token0" | "token1">("token0");
  const [removeSharesInput, setRemoveSharesInput] = useState("");
  const [slippageBps, setSlippageBps] = useState("100");
  const [notice, setNotice] = useState<{ kind: "success" | "error" | "info"; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const selectedPool = useMemo(
    () => pools.find((pool) => pool.address.toLowerCase() === selectedAddress.toLowerCase()) ?? null,
    [pools, selectedAddress],
  );

  const waitForTransaction = useCallback(async (hash: Hash) => {
    if (!client) throw new Error("Elysium RPC client is unavailable.");
    const receipt = await client.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") throw new Error("The transaction reverted on-chain.");
    return receipt;
  }, [client]);

  const requireWalletAndChain = useCallback(() => {
    if (!wallet) throw new Error("Connect your wallet first using the button at the top of the app.");
    if (chainId !== ELYSIUM_TESTNET_ID) {
      switchChain({ chainId: ELYSIUM_TESTNET_ID });
      throw new Error("Switch your wallet to Elysium Testnet, then retry the transaction.");
    }
  }, [wallet, chainId, switchChain]);

  const loadPoolPage = useCallback(async (from: number, append: boolean) => {
    if (!client || !factoryAddress) return;
    if (append) setLoadingMore(true);
    else {
      setLoading(true);
      setLoadError(null);
    }

    try {
      const [count, addresses, ownerAddress, paused] = await Promise.all([
        client.readContract({ address: factoryAddress, abi: factoryAbi, functionName: "poolCount" }),
        client.readContract({
          address: factoryAddress,
          abi: factoryAbi,
          functionName: "getPools",
          args: [BigInt(from), BigInt(PAGE_SIZE)],
        }),
        client.readContract({ address: factoryAddress, abi: factoryAbi, functionName: "owner" }),
        client.readContract({ address: factoryAddress, abi: factoryAbi, functionName: "paused" }),
      ]);

      // Bound RPC burst size for public/testnet providers; do not fan out every pool at once.
      const pageRows = await mapInBatches(addresses, 2, async (poolAddress) => {
        const [token0, token1, reserves, totalSupply, fee] = await Promise.all([
          client.readContract({ address: poolAddress, abi: poolAbi, functionName: "token0" }),
          client.readContract({ address: poolAddress, abi: poolAbi, functionName: "token1" }),
          client.readContract({ address: poolAddress, abi: poolAbi, functionName: "getReserves" }),
          client.readContract({ address: poolAddress, abi: poolAbi, functionName: "totalSupply" }),
          client.readContract({ address: poolAddress, abi: poolAbi, functionName: "feeBps" }),
        ]);

        const meta = async (token: Address) => {
          const [symbolResult, decimalsResult] = await Promise.allSettled([
            client.readContract({ address: token, abi: erc20Abi, functionName: "symbol" }),
            client.readContract({ address: token, abi: erc20Abi, functionName: "decimals" }),
          ]);
          const decimals = decimalsResult.status === "fulfilled" ? Number(decimalsResult.value) : -1;
          const symbol = symbolResult.status === "fulfilled" ? symbolResult.value : "";
          return {
            symbol: symbol || shortAddress(token),
            decimals: decimals >= 0 && decimals <= 36 ? decimals : 18,
            ok: Boolean(symbol) && decimals >= 0 && decimals <= 36,
          };
        };

        const [meta0, meta1] = await Promise.all([meta(token0), meta(token1)]);
        return {
          address: poolAddress,
          token0,
          token1,
          symbol0: meta0.symbol,
          symbol1: meta1.symbol,
          decimals0: meta0.decimals,
          decimals1: meta1.decimals,
          reserve0: reserves[0],
          reserve1: reserves[1],
          totalSupply,
          feeBps: Number(fee),
          metadataOk: meta0.ok && meta1.ok,
        } satisfies PoolInfo;
      });

      setFactoryOwner(ownerAddress);
      setProtocolPaused(paused);
      setTotalPools(count);
      setPools((current) => append ? [...current, ...pageRows] : pageRows);
      setNextStart(from + addresses.length);
      setHasMore(BigInt(from + addresses.length) < count);
      setSelectedAddress((current) => current || pageRows[0]?.address || "");
      setLoadError(null);
    } catch (error) {
      setLoadError("Could not read the pool factory: " + messageOf(error));
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [client, factoryAddress]);

  useEffect(() => {
    let cancelled = false;
    let quoteTimer: ReturnType<typeof setTimeout> | undefined;
    if (!client || !routerAddress || !selectedPool || !selectedPool.metadataOk || !swapAmountInput.trim()) {
      setSwapQuote(null);
      setQuoteError(null);
      setQuoteLoading(false);
      return () => { cancelled = true; };
    }

    try {
      const inputIs0 = swapTokenIn === "token0";
      const inputToken = inputIs0 ? selectedPool.token0 : selectedPool.token1;
      const outputToken = inputIs0 ? selectedPool.token1 : selectedPool.token0;
      const inputDecimals = inputIs0 ? selectedPool.decimals0 : selectedPool.decimals1;
      const outputDecimals = inputIs0 ? selectedPool.decimals1 : selectedPool.decimals0;
      const outputSymbol = inputIs0 ? selectedPool.symbol1 : selectedPool.symbol0;
      const amountIn = parseUnits(swapAmountInput, inputDecimals);
      if (amountIn <= 0n) {
        setSwapQuote(null);
        setQuoteError(null);
        setQuoteLoading(false);
        return () => { cancelled = true; };
      }

      setQuoteLoading(true);
      setQuoteError(null);
      const path = [inputToken, outputToken] as Address[];
      // Wait for typing to settle before calling a public RPC provider.
      quoteTimer = setTimeout(() => {
        void client.readContract({
          address: routerAddress,
          abi: routerAbi,
          functionName: "getAmountsOut",
          args: [amountIn, path],
        }).then((amounts) => {
          if (cancelled) return;
          const slippage = BigInt(Math.max(1, Math.min(500, Number(slippageBps) || 100)));
          const output = amounts[amounts.length - 1];
          const minimum = output * (10_000n - slippage) / 10_000n;
          setSwapQuote({
            output: displayAmount(output, outputDecimals),
            minimum: displayAmount(minimum, outputDecimals),
            symbol: outputSymbol,
          });
          setQuoteError(null);
        }).catch((error: unknown) => {
          if (cancelled) return;
          setSwapQuote(null);
          setQuoteError(messageOf(error));
        }).finally(() => {
          if (!cancelled) setQuoteLoading(false);
        });
      }, 250);
    } catch {
      setSwapQuote(null);
      setQuoteError(null);
      setQuoteLoading(false);
    }

    return () => {
      cancelled = true;
      if (quoteTimer !== undefined) clearTimeout(quoteTimer);
    };
  }, [client, routerAddress, selectedPool, swapAmountInput, swapTokenIn, slippageBps]);

  useEffect(() => {
    void loadPoolPage(0, false);
  }, [loadPoolPage]);

  const refresh = useCallback(async () => {
    setPools([]);
    setNextStart(0);
    setHasMore(false);
    await loadPoolPage(0, false);
  }, [loadPoolPage]);

  async function allowToken(tokenText: string) {
    setBusy(true);
    setNotice(null);
    try {
      if (!configured || !factoryAddress) throw new Error("Configure the native pool factory and router addresses first.");
      requireWalletAndChain();
      if (!factoryOwner || wallet?.toLowerCase() !== factoryOwner.toLowerCase()) {
        throw new Error("Only the pool factory owner can allowlist tokens.");
      }
      if (!isAddress(tokenText)) throw new Error("Enter a valid token contract address.");
      const token = getAddress(tokenText);
      const hash = await writeContractAsync({
        address: factoryAddress,
        abi: factoryAbi,
        functionName: "setTokenAllowed",
        args: [token, true],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(hash);
      setNotice({ kind: "success", text: "Token allowlisted. You can now create pools using it." });
      await refresh();
    } catch (error) {
      setNotice({ kind: "error", text: messageOf(error) });
    } finally {
      setBusy(false);
    }
  }

  async function setProtocolPause(paused: boolean) {
    setBusy(true);
    setNotice(null);
    try {
      if (!configured || !factoryAddress) throw new Error("Configure the native pool factory address first.");
      requireWalletAndChain();
      if (!factoryOwner || wallet?.toLowerCase() !== factoryOwner.toLowerCase()) {
        throw new Error("Only the factory owner can change protocol pause state.");
      }
      const hash = await writeContractAsync({
        address: factoryAddress,
        abi: factoryAbi,
        functionName: "setPaused",
        args: [paused],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(hash);
      setNotice({ kind: "success", text: paused ? "Emergency pause confirmed on-chain. Swaps, deposits and new pool creation are blocked; LP withdrawals remain available." : "Protocol unpaused on-chain." });
      await refresh();
    } catch (error) {
      setNotice({ kind: "error", text: messageOf(error) });
    } finally {
      setBusy(false);
    }
  }

  async function createPool() {
    setBusy(true);
    setNotice(null);
    try {
      if (!configured || !factoryAddress) throw new Error("Configure the native pool factory and router addresses first.");
      requireWalletAndChain();
      if (!isAddress(tokenAInput) || !isAddress(tokenBInput)) throw new Error("Enter both token contract addresses.");
      const tokenA = getAddress(tokenAInput);
      const tokenB = getAddress(tokenBInput);
      if (tokenA.toLowerCase() === tokenB.toLowerCase()) throw new Error("Choose two different tokens.");

      const [allowA, allowB] = await Promise.all([
        client!.readContract({ address: factoryAddress, abi: factoryAbi, functionName: "tokenAllowed", args: [tokenA] }),
        client!.readContract({ address: factoryAddress, abi: factoryAbi, functionName: "tokenAllowed", args: [tokenB] }),
      ]);
      if (!allowA || !allowB) throw new Error("Both tokens must be allowlisted by the factory owner before a pool can be created.");

      const hash = await writeContractAsync({
        address: factoryAddress,
        abi: factoryAbi,
        functionName: "createPool",
        args: [tokenA, tokenB],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(hash);
      setNotice({ kind: "success", text: "Pool created on Elysium Testnet." });
      await refresh();
    } catch (error) {
      setNotice({ kind: "error", text: messageOf(error) });
    }
  }

  async function addLiquidity() {
    setBusy(true);
    setNotice(null);
    try {
      if (!configured || !routerAddress || !selectedPool) throw new Error("Select an existing pool first.");
      requireWalletAndChain();
      if (!client || !wallet) throw new Error("Connect a wallet and try again.");
      const amount0 = parseUnits(amount0Input, selectedPool.decimals0);
      const amount1 = parseUnits(amount1Input, selectedPool.decimals1);
      if (amount0 <= 0n || amount1 <= 0n) throw new Error("Enter a positive amount for both tokens.");

      const [quoted0, quoted1, quotedShares] = await client.readContract({
        address: routerAddress,
        abi: routerAbi,
        functionName: "previewAddLiquidity",
        args: [selectedPool.token0, selectedPool.token1, amount0, amount1],
      });
      if (quotedShares <= 0n) throw new Error("This amount is too small to mint pool shares.");
      const slip = BigInt(Math.max(1, Math.min(500, Number(slippageBps) || 100)));
      const min0 = quoted0 * (10_000n - slip) / 10_000n;
      const min1 = quoted1 * (10_000n - slip) / 10_000n;
      const minShares = quotedShares * (10_000n - slip) / 10_000n;

      const approve0 = await writeContractAsync({
        address: selectedPool.token0,
        abi: erc20Abi,
        functionName: "approve",
        args: [routerAddress, amount0],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(approve0);
      const approve1 = await writeContractAsync({
        address: selectedPool.token1,
        abi: erc20Abi,
        functionName: "approve",
        args: [routerAddress, amount1],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(approve1);

      const hash = await writeContractAsync({
        address: routerAddress,
        abi: routerAbi,
        functionName: "addLiquidity",
        args: [
          selectedPool.token0,
          selectedPool.token1,
          amount0,
          amount1,
          min0,
          min1,
          minShares,
          wallet,
          BigInt(Math.floor(Date.now() / 1000) + 20 * 60),
        ],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(hash);
      setNotice({ kind: "success", text: "Liquidity added. Unused token amounts are refunded by the router." });
      setAmount0Input("");
      setAmount1Input("");
      await refresh();
    } catch (error) {
      setNotice({ kind: "error", text: messageOf(error) });
    }
  }

  async function swap() {
    setBusy(true);
    setNotice(null);
    try {
      if (!configured || !routerAddress || !selectedPool) throw new Error("Select an existing pool first.");
      requireWalletAndChain();
      if (!client || !wallet) throw new Error("Connect a wallet and try again.");
      const inputIs0 = swapTokenIn === "token0";
      const inputToken = inputIs0 ? selectedPool.token0 : selectedPool.token1;
      const outputToken = inputIs0 ? selectedPool.token1 : selectedPool.token0;
      const inputDecimals = inputIs0 ? selectedPool.decimals0 : selectedPool.decimals1;
      const outputSymbol = inputIs0 ? selectedPool.symbol1 : selectedPool.symbol0;
      const amountIn = parseUnits(swapAmountInput, inputDecimals);
      if (amountIn <= 0n) throw new Error("Enter a positive swap amount.");
      const path = [inputToken, outputToken] as Address[];
      const amounts = await client.readContract({
        address: routerAddress,
        abi: routerAbi,
        functionName: "getAmountsOut",
        args: [amountIn, path],
      });
      const slippage = BigInt(Math.max(1, Math.min(500, Number(slippageBps) || 100)));
      const amountOutMin = amounts[amounts.length - 1] * (10_000n - slippage) / 10_000n;
      if (amountOutMin <= 0n) throw new Error("Quoted output is too small.");
      const quoteText = displayAmount(amounts[amounts.length - 1], inputIs0 ? selectedPool.decimals1 : selectedPool.decimals0);

      const approval = await writeContractAsync({
        address: inputToken,
        abi: erc20Abi,
        functionName: "approve",
        args: [routerAddress, amountIn],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(approval);

      const hash = await writeContractAsync({
        address: routerAddress,
        abi: routerAbi,
        functionName: "swapExactTokensForTokens",
        args: [
          amountIn,
          amountOutMin,
          path,
          wallet,
          BigInt(Math.floor(Date.now() / 1000) + 20 * 60),
        ],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(hash);
      setNotice({ kind: "success", text: "Swap confirmed. Approximate pre-trade quote: " + quoteText + " " + outputSymbol + "." });
      setSwapAmountInput("");
      await refresh();
    } catch (error) {
      setNotice({ kind: "error", text: messageOf(error) });
    }
  }

  async function removeLiquidity() {
    setBusy(true);
    setNotice(null);
    try {
      if (!configured || !routerAddress || !selectedPool) throw new Error("Select an existing pool first.");
      requireWalletAndChain();
      if (!client || !wallet) throw new Error("Connect a wallet and try again.");
      const shares = parseUnits(removeSharesInput, 18);
      if (shares <= 0n) throw new Error("Enter a positive LP-share amount.");

      const [quoted0, quoted1] = await client.readContract({
        address: selectedPool.address,
        abi: poolAbi,
        functionName: "previewRemoveLiquidity",
        args: [shares],
      });
      const slip = BigInt(Math.max(1, Math.min(500, Number(slippageBps) || 100)));
      const min0 = quoted0 * (10_000n - slip) / 10_000n;
      const min1 = quoted1 * (10_000n - slip) / 10_000n;

      const approval = await writeContractAsync({
        address: selectedPool.address,
        abi: poolAbi,
        functionName: "approve",
        args: [routerAddress, shares],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(approval);

      const hash = await writeContractAsync({
        address: routerAddress,
        abi: routerAbi,
        functionName: "removeLiquidity",
        args: [
          selectedPool.token0,
          selectedPool.token1,
          shares,
          min0,
          min1,
          wallet,
          BigInt(Math.floor(Date.now() / 1000) + 20 * 60),
        ],
        chainId: ELYSIUM_TESTNET_ID,
      });
      await waitForTransaction(hash);
      setNotice({ kind: "success", text: "Liquidity withdrawal confirmed." });
      setRemoveSharesInput("");
      await refresh();
    } catch (error) {
      setNotice({ kind: "error", text: messageOf(error) });
    }
  }

  if (!configured || !factoryAddress || !routerAddress) {
    return (
      <section className="card section amm-config">
        <div className="section-title">Elliquid-native pools</div>
        <div className="section-meta">The pool contracts are not configured for this frontend deployment.</div>
        <p>Add <code>NEXT_PUBLIC_ELLIQUID_POOL_FACTORY_ADDRESS</code> and <code>NEXT_PUBLIC_ELLIQUID_ROUTER_ADDRESS</code> after deploying the factory and router to Elysium Testnet. The current branch has not deployed either contract.</p>
      </section>
    );
  }

  return (
    <div className="amm-page">
      <section className="card section">
        <div className="amm-heading">
          <div>
            <div className="section-title">Elliquid pool market</div>
            <div className="section-meta">First-party constant-product pools · Elysium Testnet · no external AMM dependency</div>
          </div>
          <button className="amm-button secondary" onClick={() => void refresh()} disabled={loading || isPending || busy}>
            {loading ? "Refreshing…" : "Refresh on-chain data"}
          </button>
        </div>
        <div className="amm-stats">
          <div><span>Registered pools</span><strong>{totalPools.toString()}</strong></div>
          <div><span>Network</span><strong>{chainId === ELYSIUM_TESTNET_ID ? "Elysium Testnet" : "Switch network"}</strong></div>
          <div><span>Protocol status</span><strong className={protocolPaused ? "amm-danger" : "amm-ok"}>{protocolPaused === null ? "Reading…" : protocolPaused ? "Paused" : "Active"}</strong></div>
        </div>
        {factoryOwner && wallet?.toLowerCase() === factoryOwner.toLowerCase() && (
          <div className="amm-actions">
            <button
              className={protocolPaused ? "amm-button secondary" : "amm-button danger"}
              onClick={() => void setProtocolPause(!protocolPaused)}
              disabled={busy || isPending || protocolPaused === null}
            >
              {protocolPaused ? "Unpause protocol" : "Emergency pause"}
            </button>
          </div>
        )}
        {loadError && <div className="amm-alert error">{loadError}</div>}
        {notice && <div className={"amm-alert " + notice.kind}>{notice.text}</div>}
      </section>

      <section className="card section">
        <div className="section-title">Create a pool</div>
        <div className="section-meta">New pools can only use factory-allowlisted ERC-20 tokens. Existing pool fees cannot be changed.</div>
        <div className="amm-create-grid">
          <label>Token A contract
            <input value={tokenAInput} onChange={(event) => setTokenAInput(event.target.value.trim())} placeholder="0x…" spellCheck={false} />
          </label>
          <label>Token B contract
            <input value={tokenBInput} onChange={(event) => setTokenBInput(event.target.value.trim())} placeholder="0x…" spellCheck={false} />
          </label>
        </div>
        <div className="amm-actions">
          <button
            className="amm-button secondary"
            type="button"
            onClick={() => {
              setTokenAInput("0x7D29d8047B905000459c0E80c34a26CeedcB47b2");
              setTokenBInput("0xA5b72796E5bf80443DC134F3c8a1cc97dcCC39B9");
              setNotice({ kind: "info", text: "Filled the Elysium Testnet USDC (6 decimals) / WHYPE (18 decimals) contract addresses. Verify wallet balances before providing liquidity." });
            }}
          >
            Prefill USDC / WHYPE testnet pair
          </button>
          {factoryOwner && wallet?.toLowerCase() === factoryOwner.toLowerCase() && (
            <>
              <button className="amm-button secondary" onClick={() => void allowToken(tokenAInput)} disabled={isPending || busy || !isAddress(tokenAInput)}>Allowlist token A</button>
              <button className="amm-button secondary" onClick={() => void allowToken(tokenBInput)} disabled={isPending || busy || !isAddress(tokenBInput)}>Allowlist token B</button>
            </>
          )}
          <button className="amm-button" onClick={() => void createPool()} disabled={isPending || busy || !wallet || protocolPaused === true}>
            {isPending ? "Confirm in wallet…" : "Create pool"}
          </button>
        </div>
        {factoryOwner && <div className="section-meta">Factory owner: {shortAddress(factoryOwner)} {wallet?.toLowerCase() === factoryOwner.toLowerCase() ? "· owner controls enabled" : "· token allowlisting is owner-only"}</div>}
      </section>

      <div className="amm-layout">
        <section className="card section">
          <div className="amm-heading">
            <div><div className="section-title">Pool registry</div><div className="section-meta">On-chain records, paginated at {PAGE_SIZE} pools per request.</div></div>
            <span className="amm-pill">{pools.length} loaded</span>
          </div>
          {loading && pools.length === 0 ? <div className="empty-state">Reading factory and pool state from Elysium…</div> :
            pools.length === 0 ? <div className="empty-state">No pools exist yet. Allowlist two test tokens, then create the first pair.</div> :
              <div className="amm-pool-list">
                {pools.map((pool) => (
                  <button
                    key={pool.address}
                    className={"amm-pool-row " + (pool.address === selectedAddress ? "selected" : "")}
                    onClick={() => { setSelectedAddress(pool.address); setNotice(null); }}
                  >
                    <div className="amm-pool-main">
                      <strong>{pool.symbol0} / {pool.symbol1}</strong>
                      <span>{shortAddress(pool.address)} · fee {(pool.feeBps / 100).toFixed(2)}%</span>
                    </div>
                    <div className="amm-pool-reserves">
                      <span>{displayAmount(pool.reserve0, pool.decimals0)} {pool.symbol0}</span>
                      <span>{displayAmount(pool.reserve1, pool.decimals1)} {pool.symbol1}</span>
                    </div>
                    <span className="amm-chevron">↗</span>
                  </button>
                ))}
              </div>}
          {hasMore && <button className="amm-button secondary full" onClick={() => void loadPoolPage(nextStart, true)} disabled={loadingMore || busy}>{loadingMore ? "Loading…" : "Load more pools"}</button>}
          <div className="section-meta amm-registry-meta">Pool addresses are read from the factory contract, not a placeholder list.</div>
        </section>

        <section className="card section">
          {selectedPool ? <>
            <div className="section-title">{selectedPool.symbol0} / {selectedPool.symbol1}</div>
            <div className="section-meta">{shortAddress(selectedPool.address)} · immutable {selectedPool.feeBps} bps fee</div>
            {!selectedPool.metadataOk && <div className="amm-alert error">This token pair does not expose valid ERC-20 symbol/decimals metadata. The UI disables transactions rather than guessing token units.</div>}
            <div className="amm-token-details">
              <div><span>{selectedPool.symbol0} reserve</span><strong>{displayAmount(selectedPool.reserve0, selectedPool.decimals0)}</strong><code>{shortAddress(selectedPool.token0)}</code></div>
              <div><span>{selectedPool.symbol1} reserve</span><strong>{displayAmount(selectedPool.reserve1, selectedPool.decimals1)}</strong><code>{shortAddress(selectedPool.token1)}</code></div>
              <div><span>LP shares outstanding</span><strong>{displayAmount(selectedPool.totalSupply, 18)}</strong><code>ELL-LP</code></div>
            </div>
            <label className="amm-slippage">Slippage tolerance (basis points)
              <input type="number" min="1" max="500" step="1" value={slippageBps} onChange={(event) => setSlippageBps(event.target.value)} />
              <span>1 bp = 0.01%. Maximum 500 bps (5%).</span>
            </label>

            <div className="amm-operation">
              <div className="amm-operation-title">Swap</div>
              <label>Pay with
                <select value={swapTokenIn} onChange={(event) => setSwapTokenIn(event.target.value as "token0" | "token1")}>
                  <option value="token0">{selectedPool.symbol0}</option>
                  <option value="token1">{selectedPool.symbol1}</option>
                </select>
              </label>
              <label>Exact input
                <input inputMode="decimal" value={swapAmountInput} onChange={(event) => setSwapAmountInput(event.target.value)} placeholder="0.0" />
              </label>
              <div className="amm-quote">
                {quoteLoading ? "Updating quote…" : swapQuote ? <>
                  <strong>Estimated output: {swapQuote.output} {swapQuote.symbol}</strong>
                  <span>Minimum received at current slippage: {swapQuote.minimum} {swapQuote.symbol}</span>
                </> : quoteError ? <span>Quote unavailable: {quoteError}</span> : <span>Enter an amount to preview output and minimum received.</span>}
              </div>
              <div className="section-meta">Quotes are indicative, not guaranteed. The router checks a fresh quote and enforces the minimum output you set when the swap is submitted.</div>
              <button className="amm-button" onClick={() => void swap()} disabled={isPending || busy || !wallet || !selectedPool.metadataOk || protocolPaused === true || selectedPool.totalSupply === 0n}>{isPending ? "Confirm in wallet…" : "Approve & swap"}</button>
            </div>

            <div className="amm-operation">
              <div className="amm-operation-title">Add liquidity</div>
              <div className="amm-two-inputs">
                <label>{selectedPool.symbol0} amount
                  <input inputMode="decimal" value={amount0Input} onChange={(event) => setAmount0Input(event.target.value)} placeholder="0.0" />
                </label>
                <label>{selectedPool.symbol1} amount
                  <input inputMode="decimal" value={amount1Input} onChange={(event) => setAmount1Input(event.target.value)} placeholder="0.0" />
                </label>
              </div>
              <div className="section-meta">Approvals are limited to the entered amounts. Excess tokens are refunded; the pool mints LP shares.</div>
              <button className="amm-button" onClick={() => void addLiquidity()} disabled={isPending || busy || !wallet || !selectedPool.metadataOk || protocolPaused === true}>{isPending ? "Confirm in wallet…" : "Approve & add liquidity"}</button>
            </div>

            <div className="amm-operation">
              <div className="amm-operation-title">Remove liquidity</div>
              <label>LP shares (18 decimals)
                <input inputMode="decimal" value={removeSharesInput} onChange={(event) => setRemoveSharesInput(event.target.value)} placeholder="0.0" />
              </label>
              <div className="section-meta">Withdrawals remain available if the protocol is paused. You must own the LP shares you redeem.</div>
              <button className="amm-button secondary" onClick={() => void removeLiquidity()} disabled={isPending || busy || !wallet || !selectedPool.metadataOk}>{isPending ? "Confirm in wallet…" : "Approve & remove liquidity"}</button>
            </div>
          </> : <div className="empty-state">Select a pool to trade, add liquidity or withdraw LP shares.</div>}
        </section>
      </div>
    </div>
  );
}
