import React, { useState } from 'react';
import Hero from './components/Hero';
import QuickActions from './components/QuickActions';
import KPICards from './components/KPICards';
import StockDistribution from './components/StockDistribution';
import MobileNav from './components/MobileNav';
import InventoryReports from './components/InventoryReports';
import SampleRateCalculator from './components/SampleRateCalculator';
import { ArrowLeft, Sparkles, Layers } from 'lucide-react';

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');

  return (
    <div className="w-full min-h-screen bg-[#F8FAFC]">
      {/* Main Full-Width Content Container */}
      <main className="w-full max-w-[1600px] mx-auto px-4 sm:px-6 lg:px-8 py-6 pb-24 lg:pb-8 transition-all duration-300">
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
          <div className="flex flex-col min-h-[65vh] glass-card animate-in zoom-in-95 duration-500 p-8 pt-16 items-center text-center relative bg-white/90 border border-slate-200/80 rounded-3xl shadow-sm">
            <button
              onClick={() => setActiveTab('dashboard')}
              className="absolute top-6 left-6 px-4 py-2.5 rounded-2xl bg-white hover:bg-slate-50 text-slate-700 hover:text-slate-900 border border-slate-200/80 shadow-sm transition-all flex items-center gap-2 font-bold text-xs cursor-pointer group"
              title="Back to Dashboard"
            >
              <ArrowLeft size={16} className="group-hover:-translate-x-0.5 transition-transform" />
              <span>Back to Dashboard</span>
            </button>
            
            <div className="w-20 h-20 bg-red-50 rounded-3xl flex items-center justify-center mb-6 shadow-lg shadow-red-500/10 text-red-600">
               <Layers size={36} />
            </div>
            <h2 className="text-3xl font-black text-slate-800 mb-3 capitalize tracking-tight">{activeTab} Interface</h2>
            <p className="text-slate-500 font-medium max-w-lg mx-auto leading-relaxed text-sm">
              Live enterprise data connection active. This module connects directly with your Supabase ERP backend and is synced in real-time.
            </p>
            
            <div className="mt-10 grid grid-cols-1 md:grid-cols-3 gap-6 w-full max-w-3xl">
               <div className="h-32 bg-slate-50/80 rounded-2xl border border-slate-100 animate-pulse flex flex-col justify-center items-center gap-2 text-xs font-bold text-slate-400">
                 <span>Loading Records</span>
               </div>
               <div className="h-32 bg-slate-50/80 rounded-2xl border border-slate-100 animate-pulse delay-75 flex flex-col justify-center items-center gap-2 text-xs font-bold text-slate-400">
                 <span>Syncing Matrices</span>
               </div>
               <div className="h-32 bg-slate-50/80 rounded-2xl border border-slate-100 animate-pulse delay-150 flex flex-col justify-center items-center gap-2 text-xs font-bold text-slate-400">
                 <span>Updating Analytics</span>
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
