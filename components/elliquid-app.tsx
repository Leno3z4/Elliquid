"use client";

import { useEffect, useState } from "react";
import { BarChart3, Database, LayoutDashboard, ShieldCheck } from "lucide-react";
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

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">E</div>
          <div>
            <div className="brand-name">elliquid</div>
            <div className="brand-sub">liquidity for elysium</div>
          </div>
        </div>

        <nav className="nav">
          {nav.map(([label, Icon]) => (
            <button key={label} className={active === label ? "active" : ""} onClick={() => setActive(label)}>
              <Icon size={16} />
              <span className="nav-label">{label}</span>
            </button>
          ))}
        </nav>
      </aside>

      <main className="main">
        <header className="topbar">
          <div className="topbar-title">Programmable liquidity marketplace</div>
          <div className="top-actions">
            <button className="wallet" onClick={ensureElysium}>
              {isConnected && wallet ? wallet.slice(0, 6) + "…" + wallet.slice(-4) : isConnecting ? "Connecting…" : "Connect wallet"}
            </button>
          </div>
        </header>

        <section className="content">
          <div className="hero">
            <h1>Put liquidity to work.</h1>
            <p className="hero-copy">Elliquid connects capital, Elysium projects and managed strategies into one market. Allocation and execution are governed by configured strategy and risk controls.</p>
          </div>

          {active === "Overview" && (
            <div className="overview-grid">
              <section className="card section">
                <div className="section-title">Strategies</div>
                <div className="section-meta">Live strategy configuration.</div>
                <LiveStrategies rows={strategies} empty={unavailable ?? "No active strategies found."} />
              </section>

              <section className="card section">
                <div className="section-title">Liquidity requests</div>
                <div className="section-meta">Live requests recorded by the API.</div>
                <LiveRequests rows={requests} projects={projects} empty={unavailable ?? "No liquidity requests found."} />
              </section>
            </div>
          )}

          {active === "Strategies" && (
            <section className="card section">
              <div className="section-title">Strategies</div>
              <div className="section-meta">Live strategy configuration.</div>
              <LiveStrategies rows={strategies} empty={unavailable ?? "No active strategies found."} />
            </section>
          )}

          {active === "Projects" && (
            <section className="card section">
              <div className="section-title">Projects</div>
              <div className="section-meta">Projects currently recorded by the API.</div>
              <div className="data-list">
                {projects.length ? projects.map((project) => (
                  <div className="data-row" key={project.id}>
                    <div>
                      <div className="data-name">{project.name}</div>
                      <div className="data-sub">{project.baseToken} / {project.quoteToken}</div>
                    </div>
                    <div className={"risk " + (project.verified ? "low" : "mid")}>{project.verified ? "verified" : "unverified"}</div>
                  </div>
                )) : <div className="empty-state">{unavailable ?? "No projects found."}</div>}
              </div>
            </section>
          )}

          {active === "Risk" && (
            <section className="card section">
              <div className="section-title">Risk controls</div>
              <div className="section-meta">Enforced by the strategy and contract layers.</div>
              <div className="data-list">
                <div className="data-row"><div><div className="data-name">Strategy execution</div><div className="data-sub">Controlled by the configured executor and emergency pause guardian.</div></div></div>
                <div className="data-row"><div><div className="data-name">Adapter access</div><div className="data-sub">Only approved adapters can receive vault execution.</div></div></div>
                <div className="data-row"><div><div className="data-name">Loss controls</div><div className="data-sub">Vault loss limits and adapter funding caps are enforced on-chain.</div></div></div>
              </div>
            </section>
          )}
        </section>
      </main>
    </div>
  );
}

function LiveStrategies({ rows, empty }: { rows: ApiStrategy[]; empty: string }) {
  return (
    <div className="data-list">
      {rows.length ? rows.map((strategy) => (
        <div className="data-row" key={strategy.id}>
          <div>
            <div className="data-name">{strategy.name}</div>
            <div className="data-sub">{strategy.description}</div>
          </div>
          <div className={"risk " + strategy.risk}>{strategy.risk}</div>
        </div>
      )) : <div className="empty-state">{empty}</div>}
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
            <div>
              <div className="data-name">{project?.name ?? request.projectId}</div>
              <div className="data-sub">Target {request.targetQuote} · fee {request.liquidityFeeBps} bps · {request.durationSeconds}s</div>
            </div>
            <div className={"risk " + (request.status === "open" ? "low" : "mid")}>{request.status}</div>
          </div>
        );
      }) : <div className="empty-state">{empty}</div>}
    </div>
  );
}
