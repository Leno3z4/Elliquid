"use client";

import { useEffect, useState } from "react";
import {
  formatUnits,
  getAddress,
  isAddress,
  parseUnits,
  type Address,
} from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { elysiumTestnet } from "@/lib/wagmi";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;
const FACTORY_VALUE = process.env.NEXT_PUBLIC_ELLIQUID_POOL_FACTORY_ADDRESS;
const ROUTER_VALUE = process.env.NEXT_PUBLIC_ELLIQUID_ROUTER_ADDRESS;
const FACTORY = FACTORY_VALUE && isAddress(FACTORY_VALUE) ? getAddress(FACTORY_VALUE) : undefined;
const ROUTER = ROUTER_VALUE && isAddress(ROUTER_VALUE) ? getAddress(ROUTER_VALUE) : undefined;
const BPS = 10_000n;
const POOLS_PAGE_SIZE = 20;

const factoryAbi = [
  { type: "function", name: "owner", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "paused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "allPoolsLength", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "getPools", stateMutability: "view", inputs: [{ name: "offset", type: "uint256" }, { name: "limit", type: "uint256" }], outputs: [{ type: "address[]" }] },
  { type: "function", name: "getPool", stateMutability: "view", inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }], outputs: [{ type: "address" }] },
  { type: "function", name: "allowedTokens", stateMutability: "view", inputs: [{ name: "token", type: "address" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "createPool", stateMutability: "nonpayable", inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }], outputs: [{ type: "address" }] },
  { type: "function", name: "setTokenAllowed", stateMutability: "nonpayable", inputs: [{ name: "token", type: "address" }, { name: "allowed", type: "bool" }], outputs: [] },
] as const;

const routerAbi = [
  { type: "function", name: "getAmountsOut", stateMutability: "view", inputs: [{ name: "amountIn", type: "uint256" }, { name: "path", type: "address[]" }], outputs: [{ type: "uint256[]" }] },
  { type: "function", name: "previewAddLiquidity", stateMutability: "view", inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }, { name: "amountADesired", type: "uint256" }, { name: "amountBDesired", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "previewRemoveLiquidity", stateMutability: "view", inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }, { name: "shares", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "addLiquidity", stateMutability: "nonpayable", inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }, { name: "amountADesired", type: "uint256" }, { name: "amountBDesired", type: "uint256" }, { name: "amountAMin", type: "uint256" }, { name: "amountBMin", type: "uint256" }, { name: "minShares", type: "uint256" }, { name: "recipient", type: "address" }, { name: "deadline", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "removeLiquidity", stateMutability: "nonpayable", inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }, { name: "shares", type: "uint256" }, { name: "amountAMin", type: "uint256" }, { name: "amountBMin", type: "uint256" }, { name: "recipient", type: "address" }, { name: "deadline", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "swapExactTokensForTokens", stateMutability: "nonpayable", inputs: [{ name: "amountIn", type: "uint256" }, { name: "amountOutMin", type: "uint256" }, { name: "path", type: "address[]" }, { name: "recipient", type: "address" }, { name: "deadline", type: "uint256" }], outputs: [{ type: "uint256[]" }] },
] as const;

const poolAbi = [
  { type: "function", name: "token0", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "token1", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "feeBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "getReserves", stateMutability: "view", inputs: [], outputs: [{ type: "uint112" }, { type: "uint112" }, { type: "uint256" }] },
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

const erc20Abi = [
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

type Mode = "swap" | "add" | "remove" | "create";
type ListedPool = {
  address: Address;
  token0: Address;
  token1: Address;
  symbol0: string;
  symbol1: string;
  reserve0: string;
  reserve1: string;
  feeBps: number;
};

function parseAmount(value: string, decimals?: number): bigint {
  if (!value.trim() || decimals === undefined) return 0n;
  try {
    return parseUnits(value.trim(), decimals);
  } catch {
    return 0n;
  }
}

function displayAmount(value?: bigint, decimals?: number): string {
  if (value === undefined || decimals === undefined) return "—";
  try {
    return Number(formatUnits(value, decimals)).toLocaleString(undefined, { maximumFractionDigits: 6 });
  } catch {
    return "—";
  }
}

function shortAddress(value?: string): string {
  return value ? value.slice(0, 6) + "…" + value.slice(-4) : "—";
}

export function PoolsPanel() {
  const [mode, setMode] = useState<Mode>("swap");
  const [tokenAInput, setTokenAInput] = useState("");
  const [tokenBInput, setTokenBInput] = useState("");
  const [swapAmount, setSwapAmount] = useState("1");
  const [amountAInput, setAmountAInput] = useState("10");
  const [amountBInput, setAmountBInput] = useState("10");
  const [sharesInput, setSharesInput] = useState("");
  const [slippageBps, setSlippageBps] = useState(100);
  const [notice, setNotice] = useState("");
  const [listedPools, setListedPools] = useState<ListedPool[]>([]);
  const [poolListError, setPoolListError] = useState("");
  const [poolPage, setPoolPage] = useState(0);
  const [poolRefreshVersion, setPoolRefreshVersion] = useState(0);

  const { address: wallet, chainId, isConnected } = useAccount();
  const { switchChain } = useSwitchChain();
  const client = usePublicClient({ chainId: elysiumTestnet.id });
  const tx = useWriteContract();
  const receipt = useWaitForTransactionReceipt({
    chainId: elysiumTestnet.id,
    hash: tx.data,
    query: { enabled: Boolean(tx.data) },
  });

  const tokenA = tokenAInput.trim() && isAddress(tokenAInput.trim()) ? getAddress(tokenAInput.trim()) : undefined;
  const tokenB = tokenBInput.trim() && isAddress(tokenBInput.trim()) ? getAddress(tokenBInput.trim()) : undefined;
  const validPair = Boolean(tokenA && tokenB && tokenA.toLowerCase() !== tokenB.toLowerCase());
  const networkOk = chainId === elysiumTestnet.id;
  const contractsConfigured = Boolean(FACTORY && ROUTER);

  const poolCount = useReadContract({
    chainId: elysiumTestnet.id,
    address: FACTORY ?? ZERO,
    abi: factoryAbi,
    functionName: "allPoolsLength",
    query: { enabled: Boolean(FACTORY), refetchInterval: 30000 },
  });
  const poolAddressesRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: FACTORY ?? ZERO,
    abi: factoryAbi,
    functionName: "getPools",
    args: [BigInt(poolPage * POOLS_PAGE_SIZE), BigInt(POOLS_PAGE_SIZE)],
    query: { enabled: Boolean(FACTORY), refetchInterval: 30000 },
  });
  const poolAddresses = (poolAddressesRead.data ?? []) as Address[];
  const poolAddressKey = poolAddresses.join(",");
  const totalPoolCount = Number(poolCount.data ?? 0n);
  const totalPoolPages = Math.max(1, Math.ceil(totalPoolCount / POOLS_PAGE_SIZE));

  useEffect(() => {
    if (poolPage >= totalPoolPages) setPoolPage(Math.max(0, totalPoolPages - 1));
  }, [poolPage, totalPoolPages]);

  const selectedPoolRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: FACTORY ?? ZERO,
    abi: factoryAbi,
    functionName: "getPool",
    args: [tokenA ?? ZERO, tokenB ?? ZERO],
    query: { enabled: Boolean(FACTORY && validPair), refetchInterval: 10000 },
  });
  const selectedPool = selectedPoolRead.data && selectedPoolRead.data !== ZERO
    ? selectedPoolRead.data as Address
    : undefined;
  const factoryOwnerRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: FACTORY ?? ZERO,
    abi: factoryAbi,
    functionName: "owner",
    query: { enabled: Boolean(FACTORY) },
  });
  const pausedRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: FACTORY ?? ZERO,
    abi: factoryAbi,
    functionName: "paused",
    query: { enabled: Boolean(FACTORY), refetchInterval: 10000 },
  });
  const allowedARead = useReadContract({
    chainId: elysiumTestnet.id,
    address: FACTORY ?? ZERO,
    abi: factoryAbi,
    functionName: "allowedTokens",
    args: [tokenA ?? ZERO],
    query: { enabled: Boolean(FACTORY && tokenA), refetchInterval: 10000 },
  });
  const allowedBRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: FACTORY ?? ZERO,
    abi: factoryAbi,
    functionName: "allowedTokens",
    args: [tokenB ?? ZERO],
    query: { enabled: Boolean(FACTORY && tokenB), refetchInterval: 10000 },
  });

  const decimalsARead = useReadContract({ chainId: elysiumTestnet.id, address: tokenA ?? ZERO, abi: erc20Abi, functionName: "decimals", query: { enabled: Boolean(tokenA) } });
  const decimalsBRead = useReadContract({ chainId: elysiumTestnet.id, address: tokenB ?? ZERO, abi: erc20Abi, functionName: "decimals", query: { enabled: Boolean(tokenB) } });
  const symbolARead = useReadContract({ chainId: elysiumTestnet.id, address: tokenA ?? ZERO, abi: erc20Abi, functionName: "symbol", query: { enabled: Boolean(tokenA) } });
  const symbolBRead = useReadContract({ chainId: elysiumTestnet.id, address: tokenB ?? ZERO, abi: erc20Abi, functionName: "symbol", query: { enabled: Boolean(tokenB) } });
  const decimalsA = decimalsARead.data === undefined ? undefined : Number(decimalsARead.data);
  const decimalsB = decimalsBRead.data === undefined ? undefined : Number(decimalsBRead.data);

  const rawSwap = parseAmount(swapAmount, decimalsA);
  const rawA = parseAmount(amountAInput, decimalsA);
  const rawB = parseAmount(amountBInput, decimalsB);
  const rawShares = parseAmount(sharesInput, 18);

  const allowanceARead = useReadContract({
    chainId: elysiumTestnet.id,
    address: tokenA ?? ZERO,
    abi: erc20Abi,
    functionName: "allowance",
    args: [wallet ?? ZERO, ROUTER ?? ZERO],
    query: { enabled: Boolean(wallet && tokenA && ROUTER), refetchInterval: 5000 },
  });
  const allowanceBRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: tokenB ?? ZERO,
    abi: erc20Abi,
    functionName: "allowance",
    args: [wallet ?? ZERO, ROUTER ?? ZERO],
    query: { enabled: Boolean(wallet && tokenB && ROUTER), refetchInterval: 5000 },
  });
  const lpAllowanceRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: selectedPool ?? ZERO,
    abi: poolAbi,
    functionName: "allowance",
    args: [wallet ?? ZERO, ROUTER ?? ZERO],
    query: { enabled: Boolean(wallet && selectedPool && ROUTER), refetchInterval: 5000 },
  });
  const lpBalanceRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: selectedPool ?? ZERO,
    abi: poolAbi,
    functionName: "balanceOf",
    args: [wallet ?? ZERO],
    query: { enabled: Boolean(wallet && selectedPool), refetchInterval: 5000 },
  });

  const swapQuoteRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: ROUTER ?? ZERO,
    abi: routerAbi,
    functionName: "getAmountsOut",
    args: [rawSwap, [tokenA ?? ZERO, tokenB ?? ZERO]],
    query: { enabled: Boolean(ROUTER && selectedPool && tokenA && tokenB && decimalsA !== undefined && decimalsB !== undefined && rawSwap > 0n), refetchInterval: 4000 },
  });
  const swapQuote = swapQuoteRead.data?.[1];
  const minSwapOut = swapQuote === undefined ? 0n : swapQuote * BigInt(10000 - slippageBps) / BPS;

  const addQuoteRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: ROUTER ?? ZERO,
    abi: routerAbi,
    functionName: "previewAddLiquidity",
    args: [tokenA ?? ZERO, tokenB ?? ZERO, rawA, rawB],
    query: { enabled: Boolean(ROUTER && selectedPool && tokenA && tokenB && rawA > 0n && rawB > 0n), refetchInterval: 5000 },
  });
  const addQuote = addQuoteRead.data;
  const minA = addQuote ? addQuote[0] * BigInt(10000 - slippageBps) / BPS : 0n;
  const minB = addQuote ? addQuote[1] * BigInt(10000 - slippageBps) / BPS : 0n;
  const minShares = addQuote ? addQuote[2] * BigInt(10000 - slippageBps) / BPS : 0n;

  const removeQuoteRead = useReadContract({
    chainId: elysiumTestnet.id,
    address: ROUTER ?? ZERO,
    abi: routerAbi,
    functionName: "previewRemoveLiquidity",
    args: [tokenA ?? ZERO, tokenB ?? ZERO, rawShares],
    query: { enabled: Boolean(ROUTER && selectedPool && tokenA && tokenB && rawShares > 0n), refetchInterval: 5000 },
  });
  const removeQuote = removeQuoteRead.data;
  const minRemoveA = removeQuote ? removeQuote[0] * BigInt(10000 - slippageBps) / BPS : 0n;
  const minRemoveB = removeQuote ? removeQuote[1] * BigInt(10000 - slippageBps) / BPS : 0n;

  useEffect(() => {
    if (!client || !poolAddressKey) {
      setListedPools([]);
      setPoolListError("");
      return;
    }
    const activeClient = client;
    let cancelled = false;
    const addresses = poolAddressKey.split(",").filter(Boolean) as Address[];
    async function loadPools() {
      const rows = await Promise.all(addresses.map(async (address): Promise<ListedPool> => {
        const [token0, token1, feeBps, reserves] = await Promise.all([
          activeClient.readContract({ address, abi: poolAbi, functionName: "token0" }),
          activeClient.readContract({ address, abi: poolAbi, functionName: "token1" }),
          activeClient.readContract({ address, abi: poolAbi, functionName: "feeBps" }),
          activeClient.readContract({ address, abi: poolAbi, functionName: "getReserves" }),
        ]);
        const [symbol0, decimals0, symbol1, decimals1] = await Promise.all([
          activeClient.readContract({ address: token0, abi: erc20Abi, functionName: "symbol" }),
          activeClient.readContract({ address: token0, abi: erc20Abi, functionName: "decimals" }),
          activeClient.readContract({ address: token1, abi: erc20Abi, functionName: "symbol" }),
          activeClient.readContract({ address: token1, abi: erc20Abi, functionName: "decimals" }),
        ]);
        return {
          address,
          token0,
          token1,
          symbol0,
          symbol1,
          reserve0: formatUnits(reserves[0], Number(decimals0)),
          reserve1: formatUnits(reserves[1], Number(decimals1)),
          feeBps: Number(feeBps),
        };
      }));
      if (!cancelled) {
        setListedPools(rows);
        setPoolListError("");
      }
    }
    void loadPools().catch(() => {
      if (!cancelled) setPoolListError("Could not read one or more pool token metadata contracts.");
    });
    return () => { cancelled = true; };
  }, [client, poolAddressKey, poolRefreshVersion]);

  useEffect(() => {
    if (receipt.isSuccess && receipt.data?.transactionHash) {
      setNotice("Confirmed transaction: " + receipt.data.transactionHash);
      void poolCount.refetch();
      void poolAddressesRead.refetch();
      setPoolRefreshVersion((version) => version + 1);
      void selectedPoolRead.refetch();
      void allowedARead.refetch();
      void allowedBRead.refetch();
      void allowanceARead.refetch();
      void allowanceBRead.refetch();
      void lpAllowanceRead.refetch();
      void lpBalanceRead.refetch();
    }
  }, [receipt.isSuccess, receipt.data?.transactionHash]);

  const admin = Boolean(wallet && factoryOwnerRead.data && wallet.toLowerCase() === factoryOwnerRead.data.toLowerCase());
  const allowedA = allowedARead.data === true;
  const allowedB = allowedBRead.data === true;
  const busy = tx.isPending || receipt.isLoading;

  function submit(config: Parameters<typeof tx.writeContract>[0]) {
    setNotice("");
    tx.writeContract(config);
  }

  function deadline(): bigint {
    return BigInt(Math.floor(Date.now() / 1000) + 300);
  }

  return (
    <div className="pool-page">
      <div className="pool-intro">
        <div>
          <div className="pool-kicker">ELLIQUID NATIVE AMM</div>
          <h2>Swap. Provide liquidity. Own the rails.</h2>
          <p>Elliquid’s own pool contracts are being tested on Elysium. Quotes may change before a transaction confirms.</p>
        </div>
        <div className="pool-network">{networkOk ? "Elysium testnet" : "Wallet chain " + (chainId ?? "unknown")}</div>
      </div>

      {!FACTORY || !ROUTER ? (
        <div className="pool-alert warning">Pool contracts are not configured yet. Deploy and verify the factory and router, then set their public environment variables.</div>
      ) : null}
      {pausedRead.data ? <div className="pool-alert warning">The factory is paused. Swaps and new liquidity are disabled; removing liquidity remains available.</div> : null}
      {isConnected && !networkOk ? (
        <div className="pool-alert warning">Switch to Elysium testnet before submitting transactions.
          <button className="pool-button secondary" onClick={() => switchChain({ chainId: elysiumTestnet.id })}>Switch network</button>
        </div>
      ) : null}
      <div className="pool-summary">
        <div><span>Registered pools</span><strong>{poolCount.data?.toString() ?? "—"}</strong></div>
        <div><span>Maximum pool fee</span><strong>1.00%</strong></div>
        <div><span>Default pool fee</span><strong>Configured at deployment</strong></div>
      </div>

      <section className="card section pool-workspace">
        <div className="section-head">
          <div>
            <div className="section-title">Use a pool</div>
            <div className="section-meta">Enter verified ERC-20 contract addresses. Token symbols alone do not identify an asset.</div>
          </div>
          <div className="pool-tabs">
            {(["swap", "add", "remove", "create"] as Mode[]).map((item) => (
              <button key={item} className={mode === item ? "selected" : ""} onClick={() => setMode(item)}>
                {item === "swap" ? "Swap" : item === "add" ? "Add liquidity" : item === "remove" ? "Remove liquidity" : "Create pool"}
              </button>
            ))}
          </div>
        </div>

        <div className="pool-token-grid">
          <label className="pool-field">
            <span>Token A address</span>
            <input value={tokenAInput} onChange={(event) => setTokenAInput(event.target.value)} placeholder="0x…" spellCheck={false} />
            <small>{tokenA && symbolARead.data ? String(symbolARead.data) + " · " + decimalsA + " decimals" : "Paste a token contract address"}</small>
          </label>
          <button className="pool-reverse" onClick={() => { setTokenAInput(tokenBInput); setTokenBInput(tokenAInput); }} aria-label="Reverse token pair">⇅</button>
          <label className="pool-field">
            <span>Token B address</span>
            <input value={tokenBInput} onChange={(event) => setTokenBInput(event.target.value)} placeholder="0x…" spellCheck={false} />
            <small>{tokenB && symbolBRead.data ? String(symbolBRead.data) + " · " + decimalsB + " decimals" : "Paste a token contract address"}</small>
          </label>
        </div>

        <div className="pool-selected">
          <span>Selected pool</span>
          <strong>{selectedPool ? shortAddress(selectedPool) : validPair ? "No pool found for this pair" : "Enter two different token addresses"}</strong>
        </div>

        {mode === "create" ? (
          <div className="pool-action-panel">
            <h3>Create a pair</h3>
            <p>Only factory-allowlisted tokens can be paired. Use token contracts you have independently verified. Creating a pair does not fund it; the first liquidity provider sets its starting token ratio and therefore its initial price.</p>
            {admin && tokenA && !allowedA ? (
              <button className="pool-button secondary" disabled={busy || !networkOk || !contractsConfigured} onClick={() => FACTORY && tokenA && submit({ address: FACTORY, abi: factoryAbi, functionName: "setTokenAllowed", args: [tokenA, true], chainId: elysiumTestnet.id })}>Allow Token A</button>
            ) : null}
            {admin && tokenB && !allowedB ? (
              <button className="pool-button secondary" disabled={busy || !networkOk || !contractsConfigured} onClick={() => FACTORY && tokenB && submit({ address: FACTORY, abi: factoryAbi, functionName: "setTokenAllowed", args: [tokenB, true], chainId: elysiumTestnet.id })}>Allow Token B</button>
            ) : null}
            <div className="pool-status-line">Token A: {allowedA ? "allowlisted" : "not allowlisted"} · Token B: {allowedB ? "allowlisted" : "not allowlisted"}</div>
            <button className="pool-button" disabled={!FACTORY || !ROUTER || !isConnected || !networkOk || !validPair || !allowedA || !allowedB || Boolean(selectedPool) || busy} onClick={() => FACTORY && tokenA && tokenB && submit({ address: FACTORY, abi: factoryAbi, functionName: "createPool", args: [tokenA, tokenB], chainId: elysiumTestnet.id })}>
              {selectedPool ? "Pool already exists" : "Create pool"}
            </button>
            {!admin ? <small className="pool-help">Only the factory owner can allowlist assets. Anyone can create a pool after both assets are approved.</small> : null}
          </div>
        ) : null}

        {mode === "swap" ? (
          <div className="pool-action-panel">
            <h3>Swap exact input</h3>
            <label className="pool-field">
              <span>Amount of {String(symbolARead.data ?? "Token A")}</span>
              <input value={swapAmount} onChange={(event) => setSwapAmount(event.target.value)} inputMode="decimal" placeholder="0.0" />
            </label>
            <div className="pool-quote">
              <div><span>Estimated output</span><strong>{swapQuote === undefined ? "—" : displayAmount(swapQuote, decimalsB) + " " + String(symbolBRead.data ?? "Token B")}</strong></div>
              <div><span>Minimum received</span><strong>{swapQuote === undefined ? "—" : displayAmount(minSwapOut, decimalsB) + " " + String(symbolBRead.data ?? "Token B")}</strong></div>
            </div>
            <label className="pool-field compact">
              <span>Slippage tolerance</span>
              <select value={slippageBps} onChange={(event) => setSlippageBps(Number(event.target.value))}>
                <option value={50}>0.50%</option>
                <option value={100}>1.00%</option>
                <option value={200}>2.00%</option>
              </select>
            </label>
            {(allowanceARead.data ?? 0n) < rawSwap && rawSwap > 0n ? (
              <button className="pool-button secondary" disabled={busy || !networkOk || !isConnected || !tokenA || !ROUTER} onClick={() => tokenA && ROUTER && submit({ address: tokenA, abi: erc20Abi, functionName: "approve", args: [ROUTER, rawSwap], chainId: elysiumTestnet.id })}>Approve Token A</button>
            ) : (
              <button className="pool-button" disabled={!FACTORY || !ROUTER || !isConnected || !networkOk || !selectedPool || pausedRead.data === true || rawSwap === 0n || swapQuote === undefined || busy} onClick={() => ROUTER && wallet && tokenA && tokenB && submit({ address: ROUTER, abi: routerAbi, functionName: "swapExactTokensForTokens", args: [rawSwap, minSwapOut, [tokenA, tokenB], wallet, deadline()], chainId: elysiumTestnet.id })}>Swap tokens</button>
            )}
            {swapQuoteRead.error ? <small className="pool-help">Could not quote this pair. Check the pool liquidity and token contracts.</small> : null}
          </div>
        ) : null}

        {mode === "add" ? (
          <div className="pool-action-panel">
            <h3>Add liquidity</h3>
            <div className="pool-alert warning">If this is a new or empty pool, your token ratio establishes its initial exchange price. Check both token addresses and the intended ratio before signing.</div>
            <div className="pool-amount-grid">
              <label className="pool-field"><span>{String(symbolARead.data ?? "Token A")} desired</span><input value={amountAInput} onChange={(event) => setAmountAInput(event.target.value)} inputMode="decimal" /></label>
              <label className="pool-field"><span>{String(symbolBRead.data ?? "Token B")} desired</span><input value={amountBInput} onChange={(event) => setAmountBInput(event.target.value)} inputMode="decimal" /></label>
            </div>
            <div className="pool-quote">
              <div><span>Expected token amounts</span><strong>{addQuote ? displayAmount(addQuote[0], decimalsA) + " / " + displayAmount(addQuote[1], decimalsB) : "—"}</strong></div>
              <div><span>Estimated LP shares</span><strong>{addQuote ? displayAmount(addQuote[2], 18) : "—"}</strong></div>
            </div>
            {(allowanceARead.data ?? 0n) < rawA && rawA > 0n ? (
              <button className="pool-button secondary" disabled={busy || !networkOk || !tokenA || !ROUTER} onClick={() => tokenA && ROUTER && submit({ address: tokenA, abi: erc20Abi, functionName: "approve", args: [ROUTER, rawA], chainId: elysiumTestnet.id })}>Approve Token A</button>
            ) : (allowanceBRead.data ?? 0n) < rawB && rawB > 0n ? (
              <button className="pool-button secondary" disabled={busy || !networkOk || !tokenB || !ROUTER} onClick={() => tokenB && ROUTER && submit({ address: tokenB, abi: erc20Abi, functionName: "approve", args: [ROUTER, rawB], chainId: elysiumTestnet.id })}>Approve Token B</button>
            ) : (
              <button className="pool-button" disabled={!FACTORY || !ROUTER || !isConnected || !networkOk || !selectedPool || pausedRead.data === true || rawA === 0n || rawB === 0n || !addQuote || minShares === 0n || busy} onClick={() => ROUTER && wallet && tokenA && tokenB && addQuote && submit({ address: ROUTER, abi: routerAbi, functionName: "addLiquidity", args: [tokenA, tokenB, rawA, rawB, minA, minB, minShares, wallet, deadline()], chainId: elysiumTestnet.id })}>Add liquidity</button>
            )}
            <small className="pool-help">Excess tokens are refunded to your wallet. LP shares represent proportional ownership; they do not guarantee profit.</small>
          </div>
        ) : null}

        {mode === "remove" ? (
          <div className="pool-action-panel">
            <h3>Remove liquidity</h3>
            <div className="pool-quote"><div><span>Your LP shares</span><strong>{displayAmount(lpBalanceRead.data, 18)} ELL-LP</strong></div></div>
            <label className="pool-field"><span>LP shares to remove</span><input value={sharesInput} onChange={(event) => setSharesInput(event.target.value)} inputMode="decimal" placeholder="0.0" /></label>
            <div className="pool-quote"><div><span>Estimated token output</span><strong>{removeQuote ? displayAmount(removeQuote[0], decimalsA) + " " + String(symbolARead.data ?? "A") + " / " + displayAmount(removeQuote[1], decimalsB) + " " + String(symbolBRead.data ?? "B") : "—"}</strong></div></div>
            {(lpAllowanceRead.data ?? 0n) < rawShares && rawShares > 0n ? (
              <button className="pool-button secondary" disabled={busy || !networkOk || !selectedPool || !ROUTER} onClick={() => selectedPool && ROUTER && submit({ address: selectedPool, abi: erc20Abi, functionName: "approve", args: [ROUTER, rawShares], chainId: elysiumTestnet.id })}>Approve LP shares</button>
            ) : (
              <button className="pool-button" disabled={!FACTORY || !ROUTER || !isConnected || !networkOk || !selectedPool || rawShares === 0n || !removeQuote || busy} onClick={() => ROUTER && wallet && tokenA && tokenB && removeQuote && submit({ address: ROUTER, abi: routerAbi, functionName: "removeLiquidity", args: [tokenA, tokenB, rawShares, minRemoveA, minRemoveB, wallet, deadline()], chainId: elysiumTestnet.id })}>Remove liquidity</button>
            )}
            <small className="pool-help">LP withdrawals remain enabled while factory trading is paused. Review both output estimates before signing.</small>
          </div>
        ) : null}

        {notice ? <div className="pool-alert success">{notice}</div> : null}
        {tx.error ? <div className="pool-alert error">Transaction could not be submitted: {tx.error.message.slice(0, 250)}</div> : null}
        {receipt.error ? <div className="pool-alert error">Transaction was not confirmed. Inspect wallet/explorer state before retrying.</div> : null}
        {tx.isPending ? <div className="pool-status-line">Waiting for wallet confirmation…</div> : null}
        {receipt.isLoading ? <div className="pool-status-line">Waiting for on-chain confirmation…</div> : null}
        {!isConnected ? <div className="pool-alert warning">Connect a wallet before submitting pool transactions.</div> : null}
      </section>

      <section className="card section">
        <div className="section-head">
          <div><div className="section-title">Registered pools</div><div className="section-meta">Browse {POOLS_PAGE_SIZE} pools at a time. Pool metadata loads only when the page changes or you refresh.</div></div>
          <div className="pool-status-line">{poolCount.data?.toString() ?? "—"} total</div>
        </div>
        {!FACTORY ? <div className="empty-state">Configure the verified factory address to display pools.</div> :
          listedPools.length ? (
            <div className="pool-list">
              {listedPools.map((pool) => (
                <button className="pool-list-row" key={pool.address} onClick={() => { setTokenAInput(pool.token0); setTokenBInput(pool.token1); setMode("swap"); }}>
                  <div><div className="data-name">{pool.symbol0} / {pool.symbol1}</div><div className="data-sub">{shortAddress(pool.address)} · {(pool.feeBps / 100).toFixed(2)}% fee</div></div>
                  <div className="pool-reserves"><span>{Number(pool.reserve0).toLocaleString(undefined, { maximumFractionDigits: 4 })} {pool.symbol0}</span><span>{Number(pool.reserve1).toLocaleString(undefined, { maximumFractionDigits: 4 })} {pool.symbol1}</span></div>
                </button>
              ))}
            </div>
          ) : <div className="empty-state">{poolListError || (Number(poolCount.data ?? 0n) > 0 ? "Reading pools…" : "No pools registered yet.")}</div>
        }
        <div className="pool-pagination">
          <button className="pool-button secondary" disabled={poolPage <= 0} onClick={() => setPoolPage((page) => Math.max(0, page - 1))}>Previous</button>
          <span>Page {Math.min(poolPage + 1, totalPoolPages)} of {totalPoolPages}</span>
          <button className="pool-button secondary" disabled={poolPage + 1 >= totalPoolPages} onClick={() => setPoolPage((page) => Math.min(totalPoolPages - 1, page + 1))}>Next</button>
          <button className="pool-button secondary" disabled={!FACTORY || poolAddressesRead.isFetching} onClick={() => { void poolCount.refetch(); void poolAddressesRead.refetch(); setPoolRefreshVersion((version) => version + 1); }}>Refresh pools</button>
        </div>
      </section>
      <div className="pool-disclaimer">Testnet prototype, not audited. Do not deposit valuable assets. LP positions can lose value and pool quotes are not a reliable external price oracle.</div>
    </div>
  );
}
