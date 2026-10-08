"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  fetchLiquidityRequests,
  fetchProjects,
  fetchStrategies,
  isApiConfigured,
  type ApiLiquidityRequest,
  type ApiProject,
  type ApiStrategy,
} from "@/lib/api";
import { useAccount, useConnect, useSwitchChain } from "wagmi";
import { elysiumTestnet } from "@/lib/wagmi";

export type ElliquidPage = "home" | "marketplace" | "strategies" | "projects" | "risk";

type NavigationItem = {
  page: ElliquidPage;
  href: string;
  label: string;
  short: string;
};

const navigation: NavigationItem[] = [
  { page: "home", href: "/", label: "Home", short: "HM" },
  { page: "marketplace", href: "/marketplace", label: "Marketplace", short: "MR" },
  { page: "strategies", href: "/strategies", label: "Strategies", short: "ST" },
  { page: "projects", href: "/projects", label: "Projects", short: "PR" },
  { page: "risk", href: "/risk", label: "Risk", short: "RK" },
];

const pageTitles: Record<ElliquidPage, string> = {
  home: "Programmable liquidity marketplace",
  marketplace: "Marketplace / Liquidity requests",
  strategies: "Strategies / Configuration",
  projects: "Projects / Directory",
  risk: "Risk / Controls and limits",
};

export function ElliquidApp({ page }: { page: ElliquidPage }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [strategies, setStrategies] = useState<ApiStrategy[]>([]);
  const [projects, setProjects] = useState<ApiProject[]>([]);
  const [requests, setRequests] = useState<ApiLiquidityRequest[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(() => isApiConfigured());
  const { address: wallet, isConnected, isConnecting } = useAccount();
  const { connect, connectors } = useConnect();
  const { switchChain } = useSwitchChain();
  const apiConfigured = isApiConfigured();

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
        setLoading(false);
      })
      .catch(() => {
        if (!cancelled) {
          setLoadError("Marketplace data could not be loaded.");
          setLoading(false);
        }
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

  function closeMenu() {
    setMenuOpen(false);
  }

  const walletLabel = isConnected && wallet
    ? wallet.slice(0, 6) + "…" + wallet.slice(-4)
    : isConnecting ? "Connecting…" : "Connect wallet";
  const dataState = loading
    ? "Loading market data"
    : loadError
      ? "Data unavailable"
      : apiConfigured
        ? "Data loaded"
        : "API not configured";

  return (
    <div className="app-shell">
      <a className="skip-link" href="#main-content">Skip to main content</a>

      <aside className={`sidebar${menuOpen ? " menu-open" : ""}`} aria-label="Application navigation">
        <div className="sidebar-top">
          <Link className="brand" href="/" aria-label="Elliquid home" onClick={closeMenu}>
            <span className="brand-mark" aria-hidden="true">E</span>
            <span className="brand-copy">
              <span className="brand-name">elliquid</span>
              <span className="brand-sub">liquidity for elysium</span>
            </span>
          </Link>
          <button
            className="menu-toggle"
            type="button"
            aria-expanded={menuOpen}
            aria-controls="primary-navigation"
            onClick={() => setMenuOpen((open) => !open)}
          >
            {menuOpen ? "Close" : "Menu"}
          </button>
        </div>

        <p className="nav-title">Workspace</p>
        <nav id="primary-navigation" className="primary-nav" aria-label="Main navigation">
          {navigation.map((item) => (
            <Link
              key={item.page}
              className="nav-link"
              href={item.href}
              aria-current={page === item.page ? "page" : undefined}
              aria-label={item.label}
              title={item.label}
              data-short={item.short}
              onClick={closeMenu}
            >
              <span className="nav-short" aria-hidden="true">{item.short}</span>
              <span className="nav-label-text">{item.label}</span>
            </Link>
          ))}
        </nav>

        <div className="sidebar-network">
          <p className="network-caption">Network target</p>
          <p className="network-name">Elysium Testnet</p>
          <p className="network-id">Chain ID {elysiumTestnet.id}</p>
        </div>
      </aside>

      <div className="workspace">
        <header className="topbar">
          <p className="topbar-title">{pageTitles[page]}</p>
          <div className="topbar-actions">
            <span className="network-pill" aria-label={`Network target: ${elysiumTestnet.name}, chain ID ${elysiumTestnet.id}`}>
              <span className="network-pill-full">{elysiumTestnet.name}</span>
              <span className="network-pill-short" aria-hidden="true">Testnet</span>
            </span>
            <button className="wallet-button" type="button" onClick={ensureElysium} aria-busy={isConnecting}>
              {walletLabel}
            </button>
          </div>
        </header>

        <main id="main-content" className={`content page-${page}`} tabIndex={0}>
          {page === "home" && <IntroductionPage />}
          {page === "marketplace" && (
            <MarketplacePage
              requests={requests}
              projects={projects}
              strategies={strategies}
              loading={loading}
              error={loadError}
              configured={apiConfigured}
              dataState={dataState}
            />
          )}
          {page === "strategies" && (
            <StrategiesPage rows={strategies} loading={loading} error={loadError} configured={apiConfigured} dataState={dataState} />
          )}
          {page === "projects" && (
            <ProjectsPage rows={projects} loading={loading} error={loadError} configured={apiConfigured} dataState={dataState} />
          )}
          {page === "risk" && <RiskPage />}
        </main>

        <footer className="site-footer">
          <p><span className="footer-wordmark">elliquid</span><span className="footer-separator" aria-hidden="true">/</span>Elysium Testnet</p>
          <Link href="/risk">Risk and protocol limits</Link>
        </footer>
      </div>
    </div>
  );
}

function IntroductionPage() {
  return (
    <div className="home-grid">
      <section className="home-copy" aria-labelledby="home-title">
        <h1 id="home-title">Programmable liquidity for Elysium.</h1>
        <p className="lead">
          Elliquid connects capital suppliers, Elysium projects requesting liquidity, and configured strategies.
        </p>
        <p className="home-detail">
          Review request terms, project records, strategy configuration, and protocol limits on their own pages.
        </p>
        <div className="home-actions">
          <Link className="button-primary" href="/marketplace">Browse liquidity requests</Link>
          <Link className="button-secondary" href="/risk">Review risk controls</Link>
        </div>
      </section>

      <aside className="flow-panel" aria-labelledby="flow-title">
        <h2 className="flow-title" id="flow-title">How liquidity is arranged</h2>
        <ol className="flow-list">
          <li className="flow-step">
            <span className="flow-index" aria-hidden="true">01</span>
            <div className="flow-copy"><h3>Capital suppliers</h3><p>Provide capital to managed strategy vaults.</p></div>
          </li>
          <li className="flow-step">
            <span className="flow-index" aria-hidden="true">02</span>
            <div className="flow-copy"><h3>Strategy execution</h3><p>Deploy and rebalance liquidity within configured limits.</p></div>
          </li>
          <li className="flow-step">
            <span className="flow-index" aria-hidden="true">03</span>
            <div className="flow-copy"><h3>Project requests</h3><p>State the terms for Elysium liquidity requests.</p></div>
          </li>
        </ol>
      </aside>
    </div>
  );
}

function MarketplacePage({
  requests,
  projects,
  strategies,
  loading,
  error,
  configured,
  dataState,
}: {
  requests: ApiLiquidityRequest[];
  projects: ApiProject[];
  strategies: ApiStrategy[];
  loading: boolean;
  error: string | null;
  configured: boolean;
  dataState: string;
}) {
  return (
    <>
      <PageHeading
        title="Liquidity requests"
        description="Review the target quote, duration, fee, inventory limit, and status recorded for each request."
      />
      <section className="data-panel" aria-labelledby="requests-title">
        <div className="data-panel-head">
          <h2 id="requests-title">Request records</h2>
          <span className="data-state">{dataState}</span>
        </div>
        {requests.length ? (
          <div className="request-list">
            {requests.map((request) => {
              const project = projects.find((item) => item.id === request.projectId);
              const strategy = strategies.find((item) => item.id === request.strategyId);
              return (
                <article className="request-row" key={request.id}>
                  <div className="request-heading">
                    <div className="request-title-group">
                      <h3>{project?.name ?? `Project ${request.projectId}`}</h3>
                      <p>{strategy?.name ?? `Strategy ${request.strategyId}`}</p>
                    </div>
                    <StatusLabel status={request.status} />
                  </div>
                  <dl className="request-facts">
                    <div><dt>Target quote</dt><dd>{request.targetQuote}</dd></div>
                    <div><dt>Duration</dt><dd>{formatDuration(request.durationSeconds)}</dd></div>
                    <div><dt>Liquidity fee</dt><dd>{request.liquidityFeeBps.toLocaleString("en-US")} bps</dd></div>
                    <div><dt>Max inventory</dt><dd>{request.maxInventoryBps.toLocaleString("en-US")} bps</dd></div>
                  </dl>
                </article>
              );
            })}
          </div>
        ) : (
          <EmptyState loading={loading} error={error} configured={configured} label="liquidity requests" />
        )}
      </section>
    </>
  );
}

function StrategiesPage({
  rows,
  loading,
  error,
  configured,
  dataState,
}: {
  rows: ApiStrategy[];
  loading: boolean;
  error: string | null;
  configured: boolean;
  dataState: string;
}) {
  return (
    <>
      <PageHeading
        title="Strategies"
        description="Read the description and stated risk category for each configured strategy. Configured settings are not a promise of return."
      />
      <section className="data-panel" aria-labelledby="strategies-title">
        <div className="data-panel-head">
          <h2 id="strategies-title">Strategy registry</h2>
          <span className="data-state">{dataState}</span>
        </div>
        {rows.length ? (
          <div className="registry-list">
            {rows.map((strategy) => (
              <article className="registry-row" key={strategy.id}>
                <div className="registry-copy">
                  <h3>{strategy.name}</h3>
                  <p>{strategy.description}</p>
                </div>
                <div className="registry-statuses">
                  <span className={`risk-label risk-${strategy.risk.toLowerCase()}`}>{strategy.risk} risk</span>
                  <StatusLabel status={strategy.active ? "active" : "inactive"} />
                </div>
              </article>
            ))}
          </div>
        ) : (
          <EmptyState loading={loading} error={error} configured={configured} label="strategies" />
        )}
      </section>
    </>
  );
}

function ProjectsPage({
  rows,
  loading,
  error,
  configured,
  dataState,
}: {
  rows: ApiProject[];
  loading: boolean;
  error: string | null;
  configured: boolean;
  dataState: string;
}) {
  return (
    <>
      <PageHeading
        title="Projects"
        description="Project records show the base and quote tokens and the verification state returned by the configured API."
      />
      <section className="data-panel" aria-labelledby="projects-title">
        <div className="data-panel-head">
          <h2 id="projects-title">Project registry</h2>
          <span className="data-state">{dataState}</span>
        </div>
        {rows.length ? (
          <div className="project-list">
            {rows.map((project) => (
              <article className="project-row" key={project.id}>
                <div className="project-copy">
                  <h3>{project.name}</h3>
                  <p className="token-pair"><span>{project.baseToken}</span><span aria-hidden="true">/</span><span>{project.quoteToken}</span></p>
                </div>
                <StatusLabel status={project.verified ? "verified" : "unverified"} />
              </article>
            ))}
          </div>
        ) : (
          <EmptyState loading={loading} error={error} configured={configured} label="projects" />
        )}
      </section>
    </>
  );
}

function RiskPage() {
  return (
    <>
      <PageHeading
        title="Risk and protocol limits"
        description="The repository documents controls in the contract code. These controls do not guarantee against loss and do not establish production readiness."
      />

      <aside className="risk-notice" aria-labelledby="risk-notice-title">
        <h2 id="risk-notice-title">Testnet only. Not independently audited.</h2>
        <p>
          The current UI targets Elysium Testnet. The production AMM integration and mainnet addresses are not ready.
        </p>
      </aside>

      <section className="risk-section" aria-labelledby="controls-title">
        <div className="section-heading">
          <h2 id="controls-title">Documented controls</h2>
          <p>These items are described in the repository review. This page does not verify a live deployment.</p>
        </div>
        <dl className="definition-list">
          <div><dt>Role separation</dt><dd>The review describes separate vault owner, strategy executor, and pause guardian roles. The guardian can pause execution, but cannot unpause or change economic settings.</dd></div>
          <div><dt>Adapter limits</dt><dd>Vault and adapter allowlists, single-use action keys, and per-call funding ceilings constrain execution scope.</dd></div>
          <div><dt>Loss safeguards</dt><dd>The reviewed contract code includes a loss circuit breaker and zero-NAV protection.</dd></div>
          <div><dt>Request bounds</dt><dd>Marketplace duration, inventory, and fee settings have configured limits.</dd></div>
        </dl>
      </section>

      <section className="risk-section known-risks" aria-labelledby="known-risks-title">
        <div className="section-heading">
          <h2 id="known-risks-title">Known limits</h2>
          <p>These issues remain open in the internal security review.</p>
        </div>
        <dl className="definition-list">
          <div><dt>AMM integration</dt><dd>The Elysium testnet router documented in the review is a bridge gateway, not a V2 AMM router. A production venue-specific adapter still needs verification and testing.</dd></div>
          <div><dt>NAV reporting</dt><dd>An approved adapter can report managed net asset value. Incorrect or compromised reporting can affect share pricing.</dd></div>
          <div><dt>Withdrawals</dt><dd>Immediate withdrawals require enough idle token liquidity. Managed positions may make withdrawals revert until liquidity is available.</dd></div>
          <div><dt>Independent review</dt><dd>The contracts have not been externally audited. The repository review is an internal hardening pass, not an independent audit.</dd></div>
          <div><dt>Mainnet addresses</dt><dd>Production venue and asset addresses remain unresolved in the repository. The security review says not to accept production deposits until the mainnet gate is complete.</dd></div>
        </dl>
      </section>

      <p className="risk-source">
        Source: <a href="https://github.com/Leno3z4/Elliquid/blob/main/contracts/SECURITY_REVIEW.md" target="_blank" rel="noreferrer">Elliquid repository security review</a>. This interface is not investment advice and does not promise yield.
      </p>
    </>
  );
}

function PageHeading({ title, description }: { title: string; description: string }) {
  return (
    <header className="page-heading">
      <h1 id="page-title">{title}</h1>
      <p>{description}</p>
    </header>
  );
}

function EmptyState({
  loading,
  error,
  configured,
  label,
}: {
  loading: boolean;
  error: string | null;
  configured: boolean;
  label: string;
}) {
  if (loading) {
    return <p className="empty-state" role="status">Loading {label} from the configured API.</p>;
  }
  if (error) {
    return (
      <div className="empty-state state-error" role="alert">
        <h3>Data unavailable</h3>
        <p>{error} Check the configured API endpoint before relying on this view.</p>
      </div>
    );
  }
  if (!configured) {
    return (
      <div className="empty-state" role="status">
        <h3>Live API is not configured</h3>
        <p>{label} will appear here when a data source is configured. No sample records are shown.</p>
      </div>
    );
  }
  return (
    <div className="empty-state" role="status">
      <h3>No {label} returned</h3>
      <p>The configured API returned no records for this view.</p>
    </div>
  );
}

function StatusLabel({ status }: { status: string }) {
  return <span className={`status-label status-${status.toLowerCase()}`}>{status}</span>;
}

function formatDuration(seconds: number) {
  if (seconds < 60) return `${seconds} sec`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr`;

  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  return hours ? `${days} d ${hours} hr` : `${days} d`;
}
