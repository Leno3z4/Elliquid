"use client";

import { useEffect, useMemo, useState } from "react";
import { ArrowUpRight, BarChart3, ChevronRight, Database, LayoutDashboard, Plus, ShieldCheck, Sparkles, Wallet, X, Zap } from "lucide-react";
import { ELYSIUM_TESTNET } from "@/lib/chain";
import { fetchStrategies, isApiConfigured } from "@/lib/api";
import { useAccount, useConnect, useSwitchChain } from "wagmi";
import { elysiumTestnet } from "@/lib/wagmi";

type Strategy = {
  name: string;
  desc: string;
  apy: string;
  tvl: string;
  risk: "low" | "mid" | "high";
};

const strategies: Strategy[] = [
  { name: "Elysium Market Maker", desc: "Managed two-sided liquidity with inventory limits", apy: "18.4%", tvl: "$182.4k", risk: "mid" },
  { name: "HYPE Liquidity Reserve", desc: "Native HYPE reserve management; no hedge assumed", apy: "—", tvl: "—", risk: "low" },
  { name: "Project Liquidity", desc: "Liquidity-as-a-service for vetted Elysium tokens", apy: "26.1%", tvl: "$74.9k", risk: "high" }
];

const projects = [
  { symbol: "KALO", name: "Kalos", target: "$40k", raised: "$28.6k", progress: 72, fee: "4.0%" },
  { symbol: "OX", name: "Oxley", target: "$25k", raised: "$16.1k", progress: 64, fee: "3.2%" },
  { symbol: "ELY", name: "Elypact", target: "$60k", raised: "$21.5k", progress: 36, fee: "5.5%" },
  { symbol: "ML", name: "MarketLab", target: "$30k", raised: "$24.3k", progress: 81, fee: "2.8%" }
];

const activity = [
  ["LP", "Inventory rebalance completed on KALO/USDC", "2m"],
  ["VA", "Project Liquidity vault allocated $8.4k", "11m"],
  ["WD", "0x71…5f3e withdrew 312.00 USDC", "28m"],
  ["RF", "Risk engine reduced KALO inventory by 7.5%", "41m"]
];

export function ElliquidApp() {
  const [active, setActive] = useState("Overview");
  const [modal, setModal] = useState<"deposit" | "request" | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [strategiesView, setStrategiesView] = useState<Strategy[]>(strategies);
  const [apiStatus, setApiStatus] = useState<"demo" | "loading" | "live" | "error">(isApiConfigured() ? "loading" : "demo");
  const { address: wallet, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { switchChain } = useSwitchChain();

  useEffect(() => {
    if (!isApiConfigured()) return;
    fetchStrategies()
      .then((rows) => {
        if (!rows) return;
        setStrategiesView(rows.map((row) => ({
          name: row.name,
          desc: row.description,
          apy: row.targetApy == null ? "—" : row.targetApy.toFixed(1) + "%",
          tvl: "—",
          risk: row.risk === "medium" ? "mid" : row.risk,
        })));
        setApiStatus("live");
      })
      .catch(() => setApiStatus("error"));
  }, []);

  const nav = useMemo(() => [
    ["Overview", LayoutDashboard],
    ["Strategies", BarChart3],
    ["Projects", Database],
    ["Risk", ShieldCheck]
  ] as const, []);

  function connectWallet() {
    const connector = connectors[0];
    if (!connector) {
      setToast("No injected EVM wallet connector is available.");
      return;
    }

    connect({
      connector,
      chainId: elysiumTestnet.id,
    });
  }

  function ensureElysium() {
    if (isConnected) {
      switchChain({ chainId: elysiumTestnet.id });
      return;
    }
    connectWallet();
  }

  function notify(message: string) {
    setToast(message);
    window.setTimeout(() => setToast(null), 3500);
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">E</div>
          <div><div className="brand-name">elliquid</div><div className="brand-sub">liquidity for elysium</div></div>
        </div>

        <nav className="nav">
          {nav.map(([label, Icon]) => (
            <button key={label} className={active === label ? "active" : ""} onClick={() => setActive(label)}>
              <Icon size={16} />
              <span className="nav-label">{label}</span>
            </button>
          ))}
        </nav>

        <div className="sidebar-foot">
          <div className="network">
            <div className="network-row"><span className="network-label">network</span><span className="dot" /></div>
            <div className="brand-sub">Elysium testnet · {ELYSIUM_TESTNET.chainId}</div>
          </div>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div className="topbar-title">Programmable liquidity marketplace</div>
          <div className="top-actions">
            <div className="pill"><Zap size={12}/> {apiStatus === "live" ? "D1 live" : apiStatus === "loading" ? "API loading" : apiStatus === "error" ? "API offline" : "demo data"}</div>
            <button className="wallet" onClick={ensureElysium}>{isConnected && wallet ? wallet.slice(0, 6) + "…" + wallet.slice(-4) : isPending ? "Connecting…" : "Connect wallet"}</button>
          </div>
        </header>

        <section className="content">
          <div className="hero">
            <div>
              <div className="eyebrow">{active === "Overview" ? "capital operating system" : active.toLowerCase()}</div>
              <h1>Put liquidity to work.</h1>
              <p className="hero-copy">Elliquid connects capital, Elysium projects and managed strategies into one market. Deposit once; let the risk engine decide where liquidity should sit, how much inventory to carry and when to rebalance.</p>
            </div>
            <div className="hero-action">
              <button className="secondary" onClick={() => setModal("request")}><Plus size={14}/> Request liquidity</button>
              <button className="primary" onClick={() => setModal("deposit")}><Wallet size={14}/> Deploy capital</button>
            </div>
          </div>

          <div className="stats">
            <Stat label="Total managed" value="$354.0k" foot="+12.8% this month" />
            <Stat label="Active liquidity" value="$267.2k" foot="75.5% capital deployed" />
            <Stat label="Blended strategy yield" value="19.7%" foot="after estimated fees" />
            <Stat label="Projects supported" value="14" foot="4 requests live" />
          </div>

          <div className="grid-2">
            <section className="card section">
              <div className="section-head">
                <div>
                  <div className="section-title">Strategy vaults</div>
                  <div className="section-meta">Curated strategies first. Permissionless later.</div>
                </div>
                <ChevronRight size={15} color="#778390"/>
              </div>
              <div className="strategy-list">
                {strategiesView.map((s) => (
                  <StrategyCard key={s.name} strategy={s} onOpen={() => notify(s.name + " selected — vault detail screen is next.")} />
                ))}
              </div>
            </section>

            <section className="card section">
              <div className="section-head">
                <div>
                  <div className="section-title">Capital curve</div>
                  <div className="section-meta">30-day modeled performance</div>
                </div>
                <span className="pill">demo data</span>
              </div>
              <div className="chart-wrap"><MiniChart /></div>
              <div className="chart-note"><span>30d ago</span><span>today</span></div>
              <div style={{height:14}} />
              <div className="section-head">
                <div className="section-title">Execution signals</div>
                <div className="section-meta">live risk loop</div>
              </div>
              <div className="activity">
                {activity.map(([kind, textValue, time]) => (
                  <div className="activity-row" key={textValue}>
                    <div className="activity-dot"><Sparkles size={13}/></div>
                    <div className="activity-text"><b>{kind}</b> · {textValue}</div>
                    <div className="activity-time">{time}</div>
                  </div>
                ))}
              </div>
            </section>
          </div>

          <section className="card section" style={{marginTop:12}}>
            <div className="section-head">
              <div>
                <div className="section-title">Project liquidity marketplace</div>
                <div className="section-meta">Projects request managed liquidity; vaults compete for the allocation.</div>
              </div>
              <button className="small-button" onClick={() => setModal("request")}>Create request <ArrowUpRight size={12}/></button>
            </div>

            <div className="projects">
              {projects.map(p => (
                <div className="project" key={p.symbol}>
                  <div className="token">
                    <div className="token-icon">{p.symbol.slice(0,2)}</div>
                    <div>
                      <div className="token-name">{p.name} <span style={{color:"#6f7b86",fontWeight:500}}>· {p.symbol}</span></div>
                      <div className="token-sub">target {p.target} · liquidity fee {p.fee}</div>
                    </div>
                  </div>
                  <div className="project-meta">
                    <div className="progress"><span style={{width:p.progress + "%"}} /></div>
                    <div style={{marginTop:5,color:"#727e89",fontSize:9}}>{p.progress}% funded</div>
                  </div>
                  <div className="amount">{p.raised}</div>
                  <button className="small-button" onClick={() => notify("Opening " + p.name + " liquidity request.")}>Review</button>
                </div>
              ))}
            </div>

            <div className="footer-note">Hackathon MVP uses modeled positions and testnet actions. Mainnet vaults will require audited adapters, permissions, withdrawal queues and explicit strategy risk limits before accepting real capital.</div>
          </section>
        </section>
      </main>

      {modal && <Modal type={modal} onClose={() => setModal(null)} onSubmit={(message) => { setModal(null); notify(message); }} />}
      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}

function Stat({label, value, foot}:{label:string;value:string;foot:string}) {
  return <div className="card stat"><div className="stat-label">{label}</div><div className="stat-value">{value}</div><div className="stat-foot">{foot}</div></div>;
}

function StrategyCard({strategy,onOpen}:{strategy:Strategy;onOpen:()=>void}) {
  return (
    <div className="strategy" onClick={onOpen} role="button" tabIndex={0}>
      <div><div className="strategy-name">{strategy.name}</div><div className="strategy-desc">{strategy.desc}</div></div>
      <div className="metric"><div className="metric-value">{strategy.apy}</div><div className="metric-label">target yield</div></div>
      <div><div className={"risk " + strategy.risk}>{strategy.risk} risk</div><div style={{marginTop:5,textAlign:"right",fontSize:9,color:"#6f7b86"}}>{strategy.tvl} TVL</div></div>
    </div>
  );
}

function MiniChart() {
  const points = "0,116 38,109 76,112 114,96 152,103 190,86 228,92 266,69 304,77 342,59 380,52 418,36 456,41 494,28";
  return (
    <svg className="chart" viewBox="0 0 500 145" preserveAspectRatio="none" aria-label="Modeled capital curve">
      <polyline points="0,120 500,120" fill="none" stroke="#1a2530" strokeWidth="1"/>
      <polyline points={points} fill="none" stroke="#8dff9a" strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round"/>
      <polygon points={points + " 494,128 0,128"} fill="rgba(141,255,154,.05)"/>
    </svg>
  );
}

function Modal({type,onClose,onSubmit}:{type:"deposit"|"request";onClose:()=>void;onSubmit:(message:string)=>void}) {
  const [amount,setAmount]=useState("");
  const isDeposit=type==="deposit";

  return (
    <div className="modal-backdrop" onMouseDown={e=>{if(e.currentTarget===e.target) onClose()}}>
      <div className="modal">
        <div className="modal-head">
          <div>
            <div className="modal-title">{isDeposit ? "Deploy capital" : "Request liquidity"}</div>
            <div className="modal-sub">{isDeposit ? "Choose a strategy for your testnet capital." : "Create a project-side liquidity mandate."}</div>
          </div>
          <button className="close" onClick={onClose}><X size={17}/></button>
        </div>

        <div className="form-grid">
          <div className="field"><label>{isDeposit ? "Deposit amount" : "Target liquidity"}</label><input value={amount} onChange={e=>setAmount(e.target.value)} placeholder="0.00 USDC" inputMode="decimal" /></div>
          <div className="field"><label>{isDeposit ? "Strategy" : "Preferred strategy"}</label><select defaultValue="project"><option value="market">Elysium Market Maker</option><option value="hype">HYPE Carry</option><option value="project">Project Liquidity</option></select></div>
          <div className="field"><label>{isDeposit ? "Risk cap" : "Max inventory exposure"}</label><select defaultValue="10"><option value="5">5%</option><option value="10">10%</option><option value="20">20%</option><option value="35">35%</option></select></div>
        </div>

        <div className="modal-actions">
          <button className="secondary" onClick={onClose}>Cancel</button>
          <button className="primary" onClick={() => onSubmit(isDeposit ? "Drafted a " + (amount || "0") + " USDC deployment. Wallet execution comes next." : "Liquidity request drafted for " + (amount || "0") + " USDC. Project verification comes next.")}>{isDeposit ? "Review deployment" : "Publish request"}</button>
        </div>
      </div>
    </div>
  );
}
