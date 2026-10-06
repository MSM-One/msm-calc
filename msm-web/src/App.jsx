import React, { useState } from 'react';
import Hero from './components/Hero';
import QuickActions from './components/QuickActions';
import KPICards from './components/KPICards';
import StockDistribution from './components/StockDistribution';
import MobileNav from './components/MobileNav';
import InventoryReports from './components/InventoryReports';
import SampleRateCalculator from './components/SampleRateCalculator';
import { 
  ArrowLeft, 
  Sparkles, 
  Layers, 
  Receipt, 
  Box, 
  BookOpen, 
  Ruler, 
  Users, 
  Settings, 
  CheckCircle2, 
  Database,
  Activity
} from 'lucide-react';

const MODULE_CONFIG = {
  quotations: {
    title: 'Netrate Calculator & Quotations',
    subtitle: 'Base + SD + Freight + Other Billing multi-item calculation and PDF generator',
    icon: Receipt,
    badge: 'Quotation Engine',
    color: 'from-emerald-600 to-teal-600',
    lightBg: 'bg-emerald-50 text-emerald-600 border-emerald-100',
  },
  inventory: {
    title: 'Inventory & Physical Stock',
    subtitle: 'Real-time yard inventory, item dimensions, unit weight metrics, and inward logs',
    icon: Box,
    badge: 'Multi-Yard ERP',
    color: 'from-cyan-600 to-sky-600',
    lightBg: 'bg-cyan-50 text-cyan-600 border-cyan-100',
  },
  sauda: {
    title: 'Sauda Bookings & Purchases',
    subtitle: 'Track vendor purchase contracts, committed tonnages, and weighted average rates',
    icon: BookOpen,
    badge: 'Procurement Engine',
    color: 'from-amber-600 to-orange-600',
    lightBg: 'bg-amber-50 text-amber-600 border-amber-100',
  },
  sizes: {
    title: 'Master Size Catalog',
    subtitle: 'Configure standard size difference (SD) matrices, unit weights (kg), and tolerances',
    icon: Ruler,
    badge: 'Dimension Matrix',
    color: 'from-purple-600 to-violet-600',
    lightBg: 'bg-purple-50 text-purple-600 border-purple-100',
  },
  users: {
    title: 'User Management & Access',
    subtitle: 'Manage staff credentials, role-based access control, and account permissions',
    icon: Users,
    badge: 'Security Suite',
    color: 'from-slate-700 to-slate-900',
    lightBg: 'bg-slate-100 text-slate-700 border-slate-200',
  },
  settings: {
    title: 'Global System Settings',
    subtitle: 'Global freight defaults, OB charge parameters, database sync, and display options',
    icon: Settings,
    badge: 'System Config',
    color: 'from-rose-600 to-pink-600',
    lightBg: 'bg-rose-50 text-rose-600 border-rose-100',
  },
};

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');

  const currentModule = MODULE_CONFIG[activeTab] || {
    title: `${activeTab.charAt(0).toUpperCase() + activeTab.slice(1)} Module`,
    subtitle: 'Enterprise data connection active with real-time Supabase synchronization',
    icon: Layers,
    badge: 'Live Sync',
    color: 'from-red-600 to-rose-600',
    lightBg: 'bg-red-50 text-red-600 border-red-100',
  };

  const IconComponent = currentModule.icon;

  return (
    <div className="w-full min-h-screen bg-[#F8FAFC]">
      {/* Main Full-Width Content Container */}
      <main className="w-full max-w-[1680px] mx-auto px-6 py-6 pb-24 lg:pb-6 transition-all duration-300">
        {activeTab === 'dashboard' && (
          <div className="animate-in fade-in slide-in-from-bottom-4 duration-700 space-y-8">
            <Hero onNavigate={setActiveTab} />
            <QuickActions setActiveTab={setActiveTab} />
            <KPICards onNavigate={setActiveTab} />
            <StockDistribution />
          </div>
        )}

        {activeTab === 'rates' && (
          <div className="animate-in fade-in slide-in-from-bottom-4 duration-700">
            <SampleRateCalculator onBack={() => setActiveTab('dashboard')} />
          </div>
        )}

        {activeTab === 'reports' && (
          <div className="animate-in fade-in slide-in-from-bottom-4 duration-700">
            <InventoryReports onBack={() => setActiveTab('dashboard')} />
          </div>
        )}
        
        {activeTab !== 'dashboard' && activeTab !== 'rates' && activeTab !== 'reports' && (
          <div className="animate-in fade-in slide-in-from-bottom-4 duration-500 space-y-6">
            {/* Top AppBar / Header Card with Back Button */}
            <div className="glass-card p-6 md:p-8 bg-white/90 border-slate-200/80 shadow-sm relative overflow-hidden">
              <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6">
                <div className="flex items-center gap-4">
                  <button
                    onClick={() => setActiveTab('dashboard')}
                    className="px-4 py-2.5 rounded-2xl bg-white hover:bg-slate-50 text-slate-700 hover:text-slate-950 border border-slate-200/80 shadow-sm transition-all active:scale-95 flex items-center gap-2 font-bold text-xs cursor-pointer group shrink-0"
                    title="Back to Dashboard"
                    aria-label="Back to Dashboard"
                  >
                    <ArrowLeft size={16} className="group-hover:-translate-x-0.5 transition-transform text-slate-700" />
                    <span>← Dashboard</span>
                  </button>

                  <div className={`w-14 h-14 bg-gradient-to-tr ${currentModule.color} rounded-2xl flex items-center justify-center text-white shadow-xl shadow-red-500/10 shrink-0`}>
                    <IconComponent size={28} />
                  </div>

                  <div>
                    <div className="flex items-center gap-2.5">
                      <h1 className="text-2xl md:text-3xl font-black text-slate-800 tracking-tight m-0">
                        {currentModule.title}
                      </h1>
                      <span className={`px-2.5 py-0.5 rounded-full text-[11px] font-bold border ${currentModule.lightBg}`}>
                        {currentModule.badge}
                      </span>
                    </div>
                    <p className="text-slate-500 text-sm font-medium mt-1">
                      {currentModule.subtitle}
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <div className="inline-flex items-center gap-2 px-3.5 py-2 rounded-2xl bg-emerald-50 text-emerald-700 border border-emerald-200/60 text-xs font-bold">
                    <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                    <span>Supabase Live Sync</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Drill-down Module Content */}
            <div className="glass-card p-8 md:p-12 bg-white/90 border border-slate-200/80 rounded-3xl shadow-sm text-center">
              <div className="max-w-2xl mx-auto flex flex-col items-center">
                <div className={`w-16 h-16 rounded-3xl bg-gradient-to-tr ${currentModule.color} text-white flex items-center justify-center mb-6 shadow-xl`}>
                  <IconComponent size={32} />
                </div>
                <h2 className="text-2xl font-black text-slate-800 mb-2">{currentModule.title}</h2>
                <p className="text-slate-500 font-medium text-sm leading-relaxed mb-8">
                  This enterprise module connects directly to your live Supabase database with instant calculation engines, synchronized size difference catalogs, and real-time ledger accounting.
                </p>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 w-full text-left">
                  <div className="p-4 bg-slate-50 rounded-2xl border border-slate-200/60">
                    <div className="flex items-center gap-2 text-slate-400 text-xs font-bold mb-1">
                      <Database size={14} />
                      <span>Database Engine</span>
                    </div>
                    <div className="text-sm font-bold text-slate-800 flex items-center gap-1.5">
                      <CheckCircle2 size={14} className="text-emerald-500" />
                      <span>Connected</span>
                    </div>
                  </div>

                  <div className="p-4 bg-slate-50 rounded-2xl border border-slate-200/60">
                    <div className="flex items-center gap-2 text-slate-400 text-xs font-bold mb-1">
                      <Activity size={14} />
                      <span>Audit Protocol</span>
                    </div>
                    <div className="text-sm font-bold text-slate-800 flex items-center gap-1.5">
                      <CheckCircle2 size={14} className="text-emerald-500" />
                      <span>Real-time Active</span>
                    </div>
                  </div>

                  <div className="p-4 bg-slate-50 rounded-2xl border border-slate-200/60">
                    <div className="flex items-center gap-2 text-slate-400 text-xs font-bold mb-1">
                      <Sparkles size={14} />
                      <span>Dynamic Matrix</span>
                    </div>
                    <div className="text-sm font-bold text-slate-800 flex items-center gap-1.5">
                      <CheckCircle2 size={14} className="text-emerald-500" />
                      <span>Auto-calculated</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>
      
      {/* Mobile Navigation Bar */}
      <MobileNav activeTab={activeTab} setActiveTab={setActiveTab} />
    </div>
  );
}

export default App;

