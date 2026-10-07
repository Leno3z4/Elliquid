"use client";

import { useEffect, useState } from "react";
import { fetchLiquidityRequests, fetchProjects, fetchStrategies, isApiConfigured, type ApiLiquidityRequest, type ApiProject, type ApiStrategy } from "@/lib/api";
import { useAccount, useConnect, useSwitchChain } from "wagmi";
import { elysiumTestnet } from "@/lib/wagmi";

const views = ["Overview", "Strategies", "Projects", "Risk"] as const;
type View = (typeof views)[number];

export function ElliquidApp() {
  const [active, setActive] = useState<View>("Overview");
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

  const walletLabel = isConnected && wallet
    ? wallet.slice(0, 6) + "…" + wallet.slice(-4)
    : isConnecting ? "Connecting…" : "Connect wallet";
  const dataState = loading ? "Loading market data" : loadError ? "Data unavailable" : apiConfigured ? "Data loaded" : "API not configured";
  const dataNote = loading
    ? "Loading configured strategies, projects and requests."
    : loadError
      ? "Check the configured API endpoint before relying on this view."
      : apiConfigured
        ? "Counts reflect the records returned by the configured API."
        : "Marketplace records will appear when the API is configured.";

  function closeMenu() {
    setMenuOpen(false);
  }

  return (
    <main className="site-shell" id="home">
      <header className="site-nav">
        <a className="wordmark" href="#home" aria-label="Elliquid home" onClick={closeMenu}>elliquid<span>.</span></a>
        <button
          className="menu-toggle"
          type="button"
          aria-expanded={menuOpen}
          aria-controls="primary-navigation"
          onClick={() => setMenuOpen((open) => !open)}
        >
          {menuOpen ? "Close" : "Menu"}
        </button>
        <nav id="primary-navigation" className={`primary-nav${menuOpen ? " is-open" : ""}`} aria-label="Main navigation">
          <a href="#what-to-inspect" onClick={closeMenu}>What to inspect</a>
          <a href="#marketplace" onClick={closeMenu}>Marketplace</a>
          <a href="#risk-controls-note" onClick={closeMenu}>Risk note</a>
        </nav>
        <button className="wallet-button" type="button" onClick={ensureElysium}>
          {walletLabel}
        </button>
      </header>

      <section className="hero-section" aria-labelledby="hero-title">
        <div className="hero-copy">
          <p className="hero-kicker">ELLIQUID / ELYSIUM</p>
          <h1 id="hero-title">A market for<br />Elysium <em>liquidity.</em></h1>
          <p className="hero-description">Elliquid brings projects, liquidity requests and configured strategies into one place, so capital providers can review the terms and controls before acting.</p>
          <div className="hero-actions">
            <a className="button-primary" href="#marketplace">View the marketplace</a>
            <a className="button-secondary" href="#what-to-inspect">What can I inspect?</a>
          </div>
          <p className="hero-context">Built around the records and controls the marketplace actually exposes.</p>
        </div>

        <aside className="market-note" aria-labelledby="market-note-title" aria-live="polite">
          <div className="note-topline"><span>MARKET RECORD</span><span className="data-state">{dataState}</span></div>
          <h2 id="market-note-title">At a glance</h2>
          <dl className="record-counts">
            <div><dt>Strategies</dt><dd>{countText(strategies.length, loading, apiConfigured, loadError)}</dd></div>
            <div><dt>Projects</dt><dd>{countText(projects.length, loading, apiConfigured, loadError)}</dd></div>
            <div><dt>Liquidity requests</dt><dd>{countText(requests.length, loading, apiConfigured, loadError)}</dd></div>
          </dl>
          <p className="note-explanation">{dataNote}</p>
          <a className="note-link" href="#marketplace">Open marketplace <span aria-hidden="true">↘</span></a>
        </aside>
        <div className="hero-index" aria-hidden="true">01 <span /> MARKET STRUCTURE</div>
      </section>

      <section className="inspection-section" id="what-to-inspect" aria-labelledby="inspection-title">
        <div className="inspection-heading">
          <p className="section-label">BEFORE YOU ALLOCATE</p>
          <h2 id="inspection-title">Terms first.<br /><em>Then a decision.</em></h2>
        </div>
        <div className="inspection-copy">
          <p className="inspection-intro">The marketplace is organized around the information that shapes a liquidity decision, not a headline yield.</p>
          <dl className="inspection-list">
            <div><dt>Request terms</dt><dd>Review target quote, liquidity fee and duration on each recorded request.</dd></div>
            <div><dt>Project record</dt><dd>See the project's base and quote tokens, along with its verification state.</dd></div>
            <div><dt>Strategy posture</dt><dd>Read each configured strategy's description and stated risk category.</dd></div>
          </dl>
        </div>
      </section>

      <section className="market-section" id="marketplace" aria-labelledby="marketplace-title">
        <div className="market-heading">
          <div>
            <p className="section-label">THE ELLIQUID MARKETPLACE</p>
            <h2 id="marketplace-title">Read the <em>market.</em></h2>
          </div>
          <p>Browse the configured records. Connect your wallet when you are ready to use the Elysium network.</p>
        </div>

        <div className="market-frame">
          <div className="market-toolbar">
            <nav className="market-tabs" aria-label="Marketplace views">
              {views.map((view) => (
                <button
                  key={view}
                  type="button"
                  className={active === view ? "selected" : ""}
                  aria-pressed={active === view}
                  onClick={() => setActive(view)}
                >
                  {view}
                </button>
              ))}
            </nav>
            <span className="network-label">ELYSIUM TESTNET</span>
          </div>

          <div className="market-content">
            {active === "Overview" && (
              <>
                <div className="view-heading"><div><p className="section-label">OVERVIEW</p><h3>Current records</h3></div><span className="view-count">{dataState}</span></div>
                <div className="overview-lists">
                  <section className="dataset" aria-labelledby="overview-strategies">
                    <div className="dataset-heading"><h4 id="overview-strategies">Strategies</h4><span>{countText(strategies.length, loading, apiConfigured, loadError)}</span></div>
                    <LiveStrategies rows={strategies.slice(0, 3)} loading={loading} error={loadError} configured={apiConfigured} />
                  </section>
                  <section className="dataset" aria-labelledby="overview-requests">
                    <div className="dataset-heading"><h4 id="overview-requests">Liquidity requests</h4><span>{countText(requests.length, loading, apiConfigured, loadError)}</span></div>
                    <LiveRequests rows={requests.slice(0, 3)} projects={projects} loading={loading} error={loadError} configured={apiConfigured} />
                  </section>
                </div>
              </>
            )}

            {active === "Strategies" && (
              <section className="dataset dataset-full" aria-labelledby="strategies-title">
                <div className="view-heading"><div><p className="section-label">CONFIGURATION</p><h3 id="strategies-title">Strategies</h3></div><span className="view-count">{countText(strategies.length, loading, apiConfigured, loadError)}</span></div>
                <LiveStrategies rows={strategies} loading={loading} error={loadError} configured={apiConfigured} />
              </section>
            )}

            {active === "Projects" && (
              <section className="dataset dataset-full" aria-labelledby="projects-title">
                <div className="view-heading"><div><p className="section-label">PROJECT RECORDS</p><h3 id="projects-title">Projects</h3></div><span className="view-count">{countText(projects.length, loading, apiConfigured, loadError)}</span></div>
                <LiveProjects rows={projects} loading={loading} error={loadError} configured={apiConfigured} />
              </section>
            )}

            {active === "Risk" && (
              <section className="risk-view" id="risk-controls" aria-labelledby="risk-title">
                <div className="view-heading"><div><p className="section-label">PROTOCOL CONTROLS</p><h3 id="risk-title">Execution guardrails</h3></div></div>
                <p className="risk-intro">These controls are enforced in the strategy and contract layers. They describe protocol behavior, not a guarantee against loss.</p>
                <dl className="risk-list">
                  <div><dt>Executor and pause</dt><dd>Strategy execution is controlled by the configured executor and emergency pause guardian.</dd></div>
                  <div><dt>Approved adapters</dt><dd>Only approved adapters can receive vault execution.</dd></div>
                  <div><dt>Loss and funding limits</dt><dd>Vault loss limits and adapter funding caps are enforced on-chain.</dd></div>
                </dl>
              </section>
            )}
          </div>
        </div>
        <p className="market-disclaimer" id="risk-controls-note">Configured records are not investment advice. Review each request and the relevant on-chain details before interacting.</p>
      </section>

      <footer className="site-footer">
        <a className="wordmark" href="#home">elliquid<span>.</span></a>
        <p>Liquidity records for the Elysium ecosystem.</p>
        <a href="#risk-controls-note">Risk note</a>
      </footer>
    </main>
  );
}

function countText(count: number, loading: boolean, configured: boolean, error: string | null) {
  if (loading) return "Loading";
  if (error) return "Unavailable";
  if (!configured) return "Not connected";
  return count.toLocaleString("en-US");
}

function EmptyState({ loading, error, configured, label }: { loading: boolean; error: string | null; configured: boolean; label: string }) {
  if (loading) {
    return <p className="state-message" role="status">Loading {label} from the configured API.</p>;
  }
  if (error) {
    return <p className="state-message state-error" role="alert">{error} Check the configured API endpoint and try again later.</p>;
  }
  if (!configured) {
    return <p className="state-message">The API is not configured. {label} will appear here when a data source is connected.</p>;
  }
  return <p className="state-message">No {label} were returned by the configured API.</p>;
}

function LiveStrategies({ rows, loading, error, configured }: { rows: ApiStrategy[]; loading: boolean; error: string | null; configured: boolean }) {
  if (!rows.length) return <EmptyState loading={loading} error={error} configured={configured} label="strategies" />;
  return (
    <div className="record-list">
      {rows.map((strategy) => (
        <article className="record-row" key={strategy.id}>
          <div className="record-main"><h5>{strategy.name}</h5><p>{strategy.description}</p></div>
          <span className={`risk-level risk-${strategy.risk.toLowerCase()}`}>{strategy.risk}</span>
        </article>
      ))}
    </div>
  );
}

function LiveRequests({ rows, projects, loading, error, configured }: { rows: ApiLiquidityRequest[]; projects: ApiProject[]; loading: boolean; error: string | null; configured: boolean }) {
  if (!rows.length) return <EmptyState loading={loading} error={error} configured={configured} label="liquidity requests" />;
  return (
    <div className="record-list">
      {rows.map((request) => {
        const project = projects.find((item) => item.id === request.projectId);
        return (
          <article className="record-row" key={request.id}>
            <div className="record-main"><h5>{project?.name ?? request.projectId}</h5><p>Target {request.targetQuote} / fee {request.liquidityFeeBps} bps / {request.durationSeconds} seconds</p></div>
            <span className={`risk-level ${request.status === "open" ? "risk-open" : "risk-closed"}`}>{request.status}</span>
          </article>
        );
      })}
    </div>
  );
}

function LiveProjects({ rows, loading, error, configured }: { rows: ApiProject[]; loading: boolean; error: string | null; configured: boolean }) {
  if (!rows.length) return <EmptyState loading={loading} error={error} configured={configured} label="projects" />;
  return (
    <div className="record-list">
      {rows.map((project) => (
        <article className="record-row" key={project.id}>
          <div className="record-main"><h5>{project.name}</h5><p>{project.baseToken} / {project.quoteToken}</p></div>
          <span className={`risk-level ${project.verified ? "risk-open" : "risk-closed"}`}>{project.verified ? "Verified" : "Unverified"}</span>
        </article>
      ))}
    </div>
  );
}
