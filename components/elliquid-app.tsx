"use client";

import { useEffect, useState } from "react";
import {
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  BarChart3,
  Check,
  Database,
  LayoutDashboard,
  LockKeyhole,
  ShieldCheck,
  Wallet,
} from "lucide-react";
import { fetchLiquidityRequests, fetchProjects, fetchStrategies, isApiConfigured, type ApiLiquidityRequest, type ApiProject, type ApiStrategy } from "@/lib/api";
import { useAccount, useConnect, useSwitchChain } from "wagmi";
import { elysiumTestnet } from "@/lib/wagmi";

const nav = [
  ["Overview", LayoutDashboard],
  ["Strategies", BarChart3],
  ["Projects", Database],
  ["Risk", ShieldCheck],
] as const;

export function ElliquidApp() {
  const [active, setActive] = useState("Overview");
  const [strategies, setStrategies] = useState<ApiStrategy[]>([]);
  const [projects, setProjects] = useState<ApiProject[]>([]);
  const [requests, setRequests] = useState<ApiLiquidityRequest[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const { address: wallet, isConnected, isConnecting } = useAccount();
  const { connect, connectors } = useConnect();
  const { switchChain } = useSwitchChain();

  useEffect(() => {
    if (!isApiConfigured()) return;
    let cancelled = false;

    Promise.all([fetchStrategies(), fetchProjects(), fetchLiquidityRequests()])
      .then(([strategyRows, projectRows, requestRows]) => {
        if (cancelled) return;
        setStrategies(strategyRows ?? []);
        setProjects(projectRows ?? []);
        setRequests(requestRows ?? []);
        setLoadError(null);
      })
      .catch(() => {
        if (!cancelled) setLoadError("Live data could not be loaded.");
      });

    return () => {
      cancelled = true;
    };
  }, []);

  function connectWallet() {
    const connector = connectors[0];
    if (connector) connect({ connector, chainId: elysiumTestnet.id });
  }

  function ensureElysium() {
    if (isConnected) {
      switchChain({ chainId: elysiumTestnet.id });
    } else {
      connectWallet();
    }
  }

  const unavailable = loadError ?? (isApiConfigured() ? null : "Live API is not configured.");
  const walletLabel = isConnected && wallet
    ? wallet.slice(0, 6) + "…" + wallet.slice(-4)
    : isConnecting ? "Connecting…" : "Connect wallet";

  return (
    <main className="site-shell">
      <header className="site-nav">
        <a className="brand" href="#home" aria-label="Elliquid home">
          <span className="brand-mark"><span /></span>
          <span className="brand-name">elliquid<span className="brand-period">.</span></span>
        </a>
        <nav className="site-links" aria-label="Main navigation">
          <a href="#how-it-works">How it works</a>
          <a href="#transparency">Transparency</a>
          <a href="#marketplace">Marketplace</a>
        </nav>
        <button className="wallet-button" onClick={ensureElysium}>
          <Wallet size={16} />
          <span>{walletLabel}</span>
          <ArrowUpRight size={14} className="wallet-arrow" />
        </button>
      </header>

      <section className="landing-hero" id="home">
        <div className="hero-copy-block">
          <div className="eyebrow"><span className="status-dot" /> BUILT FOR ELYSIUM</div>
          <h1>Liquidity that<br /><em>moves markets.</em></h1>
          <p className="hero-lede">A programmable liquidity layer connecting capital, Elysium projects and managed strategies — with risk controls designed into every allocation.</p>
          <div className="hero-actions">
            <a className="button-primary" href="#marketplace">Explore marketplace <ArrowRight size={17} /></a>
            <a className="text-link" href="#how-it-works">See how it works <ArrowDownRight size={16} /></a>
          </div>
          <div className="hero-note"><LockKeyhole size={14} /> Strategy-led execution. On-chain guardrails.</div>
        </div>

        <div className="hero-art" aria-label="Abstract liquidity flow visualization">
          <div className="orbit orbit-outer" />
          <div className="orbit orbit-inner" />
          <div className="orbit orbit-dash" />
          <div className="flow-line flow-one" />
          <div className="flow-line flow-two" />
          <div className="flow-line flow-three" />
          <div className="flow-node node-a"><span>01</span><b>CAPITAL</b></div>
          <div className="flow-node node-b"><span>02</span><b>STRATEGY</b></div>
          <div className="flow-node node-c"><span>03</span><b>PROJECT</b></div>
          <div className="flow-core"><div className="core-mark"><span /></div><span>ELLIQUID</span><small>LIQUIDITY LAYER</small></div>
          <div className="orbit-label label-top">DEPLOY WITH PURPOSE</div>
          <div className="orbit-label label-bottom">E L Y S I U M · E C O S Y S T E M</div>
        </div>
        <div className="hero-index"><span>01</span><span className="index-rule" /><span>LIQUIDITY, REIMAGINED</span></div>
      </section>

      <section className="signal-strip" id="transparency">
        <div className="signal-intro"><span className="signal-kicker">A CLEARER WAY TO DEPLOY</span><p>Capital should move<br />with <em>context.</em></p></div>
        <div className="signal-item"><span className="signal-icon"><BarChart3 size={18} /></span><div><b>Strategy-led</b><p>Allocation follows configured strategies, not guesswork.</p></div></div>
        <div className="signal-item"><span className="signal-icon"><ShieldCheck size={18} /></span><div><b>Risk-aware</b><p>Controls are part of the execution path.</p></div></div>
        <div className="signal-item"><span className="signal-icon"><Database size={18} /></span><div><b>Built for builders</b><p>Connect liquidity with projects across Elysium.</p></div></div>
      </section>

      <section className="how-section" id="how-it-works">
        <div className="section-overline">THE ELLIQUID APPROACH <span>01 — 03</span></div>
        <div className="how-heading"><h2>From idle capital<br />to <em>useful liquidity.</em></h2><p>One connected marketplace. A transparent path from liquidity request to strategy-guided execution.</p></div>
        <div className="steps-grid">
          <article className="step-card"><span className="step-no">01</span><div className="step-icon"><Wallet size={20} /></div><h3>Connect</h3><p>Connect your wallet to the Elysium ecosystem and explore available opportunities.</p><span className="step-foot">YOUR WALLET, YOUR CONTROL</span></article>
          <article className="step-card"><span className="step-no">02</span><div className="step-icon"><BarChart3 size={20} /></div><h3>Discover</h3><p>Review live projects, liquidity requests and the strategies configured for each market.</p><span className="step-foot">CLEAR BEFORE COMMITMENT</span></article>
          <article className="step-card"><span className="step-no">03</span><div className="step-icon"><ShieldCheck size={20} /></div><h3>Deploy</h3><p>Execution is governed by strategy permissions and protocol-level risk controls.</p><span className="step-foot">GUARDED BY DESIGN</span></article>
        </div>
      </section>

      <section className="market-section" id="marketplace">
        <div className="market-heading">
          <div><div className="section-overline">THE MARKETPLACE <span>LIVE VIEW</span></div><h2>See the <em>landscape.</em></h2></div>
          <p>Explore configured strategies, projects and liquidity requests. Connect to Elysium to take part.</p>
        </div>
        <div className="app-shell">
          <aside className="sidebar">
            <div className="side-label">WORKSPACE</div>
            <nav className="nav" aria-label="Marketplace views">
              {nav.map(([label, Icon]) => (
                <button key={label} className={active === label ? "active" : ""} onClick={() => setActive(label)} aria-current={active === label ? "page" : undefined}>
                  <Icon size={16} /><span className="nav-label">{label}</span>{active === label && <span className="nav-indicator" />}
                </button>
              ))}
            </nav>
            <div className="sidebar-foot"><span className="status-dot" /> ELYSIUM TESTNET</div>
          </aside>

          <div className="market-main">
            <header className="market-topbar">
              <div><span className="breadcrumb">MARKETPLACE</span><span className="breadcrumb-sep">/</span><span>{active}</span></div>
              <button className="market-wallet" onClick={ensureElysium}>{walletLabel}</button>
            </header>
            <div className="market-content">
              <div className="dashboard-heading">
                <div><span className="dashboard-eyebrow">ELLIQUID · ELYSIUM</span><h3>{active === "Overview" ? "Market overview" : active}</h3><p>Programmable liquidity, with the context to move confidently.</p></div>
                <span className="network-pill"><span className="status-dot" /> Elysium</span>
              </div>

              {active === "Overview" && (
                <div className="overview-grid">
                  <section className="card section">
                    <div className="section-head"><div><div className="section-title">Strategies</div><div className="section-meta">Configured for the marketplace</div></div><span className="card-count">{strategies.length.toString().padStart(2, "0")}</span></div>
                    <LiveStrategies rows={strategies} empty={unavailable ?? "No active strategies found."} />
                  </section>
                  <section className="card section">
                    <div className="section-head"><div><div className="section-title">Liquidity requests</div><div className="section-meta">Requests recorded by the API</div></div><span className="card-count">{requests.length.toString().padStart(2, "0")}</span></div>
                    <LiveRequests rows={requests} projects={projects} empty={unavailable ?? "No liquidity requests found."} />
                  </section>
                </div>
              )}

              {active === "Strategies" && (
                <section className="card section"><div className="section-head"><div><div className="section-title">Strategies</div><div className="section-meta">Configured for the marketplace</div></div></div><LiveStrategies rows={strategies} empty={unavailable ?? "No active strategies found."} /></section>
              )}

              {active === "Projects" && (
                <section className="card section"><div className="section-head"><div><div className="section-title">Projects</div><div className="section-meta">Projects currently recorded by the API</div></div><span className="card-count">{projects.length.toString().padStart(2, "0")}</span></div>
                  <div className="data-list">{projects.length ? projects.map((project) => (
                    <div className="data-row" key={project.id}><div><div className="data-name">{project.name}</div><div className="data-sub">{project.baseToken} / {project.quoteToken}</div></div><div className={"risk " + (project.verified ? "low" : "mid")}>{project.verified ? <><Check size={12} /> verified</> : "unverified"}</div></div>
                  )) : <div className="empty-state"><span className="empty-symbol"><Database size={18} /></span><b>{unavailable ?? "No projects found."}</b><span>Projects will appear here when available.</span></div>}</div>
                </section>
              )}

              {active === "Risk" && (
                <section className="card section"><div className="section-head"><div><div className="section-title">Risk controls</div><div className="section-meta">Enforced by the strategy and contract layers</div></div><span className="risk-overview"><ShieldCheck size={14} /> PROTOCOL CONTROLS</span></div>
                  <div className="data-list">
                    <div className="data-row"><span className="control-check"><Check size={13} /></span><div><div className="data-name">Strategy execution</div><div className="data-sub">Controlled by the configured executor and emergency pause guardian.</div></div></div>
                    <div className="data-row"><span className="control-check"><Check size={13} /></span><div><div className="data-name">Adapter access</div><div className="data-sub">Only approved adapters can receive vault execution.</div></div></div>
                    <div className="data-row"><span className="control-check"><Check size={13} /></span><div><div className="data-name">Loss controls</div><div className="data-sub">Vault loss limits and adapter funding caps are enforced on-chain.</div></div></div>
                  </div>
                </section>
              )}
              <div className="market-footnote"><LockKeyhole size={13} /> Data reflects configured API records. Nothing here represents a guaranteed return.</div>
            </div>
          </div>
        </div>
      </section>

      <footer className="site-footer"><a className="brand footer-brand" href="#home"><span className="brand-mark"><span /></span><span className="brand-name">elliquid<span className="brand-period">.</span></span></a><span>Liquidity for the Elysium ecosystem.</span><span className="footer-right">PROGRAMMABLE LIQUIDITY <ArrowUpRight size={13} /></span></footer>
    </main>
  );
}

function LiveStrategies({ rows, empty }: { rows: ApiStrategy[]; empty: string }) {
  return (
    <div className="data-list">
      {rows.length ? rows.map((strategy) => (
        <div className="data-row" key={strategy.id}>
          <div><div className="data-name">{strategy.name}</div><div className="data-sub">{strategy.description}</div></div>
          <div className={"risk " + strategy.risk}>{strategy.risk}</div>
        </div>
      )) : <div className="empty-state"><span className="empty-symbol"><BarChart3 size={18} /></span><b>{empty}</b><span>When configured, strategy details will appear here.</span></div>}
    </div>
  );
}

function LiveRequests({ rows, projects, empty }: { rows: ApiLiquidityRequest[]; projects: ApiProject[]; empty: string }) {
  return (
    <div className="data-list">
      {rows.length ? rows.map((request) => {
        const project = projects.find((item) => item.id === request.projectId);
        return (
          <div className="data-row" key={request.id}>
            <div><div className="data-name">{project?.name ?? request.projectId}</div><div className="data-sub">Target {request.targetQuote} · fee {request.liquidityFeeBps} bps · {request.durationSeconds}s</div></div>
            <div className={"risk " + (request.status === "open" ? "low" : "mid")}>{request.status}</div>
          </div>
        );
      }) : <div className="empty-state"><span className="empty-symbol"><Database size={18} /></span><b>{empty}</b><span>Request activity will appear here when available.</span></div>}
    </div>
  );
}
