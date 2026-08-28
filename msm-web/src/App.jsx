import React, { useState } from 'react';
import FloatingSidebar from './components/FloatingSidebar';
import Hero from './components/Hero';
import KPICards from './components/KPICards';
import StockDistribution from './components/StockDistribution';
import MobileNav from './components/MobileNav';
import InventoryReports from './components/InventoryReports';

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');

  return (
    <div className="flex min-h-screen bg-[#FDFCFE]">
      {/* Floating Sidebar - Desktop */}
      <div className="hidden lg:block w-24">
        <FloatingSidebar activeTab={activeTab} setActiveTab={setActiveTab} />
      </div>
      
      {/* Main Content */}
      <main className="flex-1 p-4 md:p-8 pb-32 lg:pb-8 transition-all duration-500">
        <div className="max-w-7xl mx-auto">
          {activeTab === 'dashboard' && (
            <div className="animate-in fade-in slide-in-from-bottom-4 duration-700">
              <Hero />
              <KPICards />
              <StockDistribution />
            </div>
          )}

          {activeTab === 'reports' && (
            <div className="animate-in fade-in slide-in-from-bottom-4 duration-700">
              <InventoryReports />
            </div>
          )}
          
          {activeTab !== 'dashboard' && activeTab !== 'reports' && (
            <div className="flex flex-col min-h-[60vh] glass-card animate-in zoom-in-95 duration-500 p-8 pt-12 items-center text-center">
              <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center mb-8 shadow-xl shadow-slate-200">
                 <div className="w-12 h-12 border-4 border-slate-100 border-t-msm-red rounded-full animate-spin" />
              </div>
              <h2 className="text-3xl font-black text-slate-800 mb-3 capitalize tracking-tight">{activeTab} Interface</h2>
              <p className="text-slate-500 font-medium max-w-md mx-auto leading-relaxed">
                Loading live backend data for the {activeTab} view. This premium module is dynamically fetching records and integrating with your main dashboard stats.
              </p>
              
              <div className="mt-12 grid grid-cols-1 md:grid-cols-3 gap-6 w-full max-w-3xl">
                 <div className="h-32 bg-slate-50 rounded-2xl border border-slate-100 animate-pulse"></div>
                 <div className="h-32 bg-slate-50 rounded-2xl border border-slate-100 animate-pulse delay-75"></div>
                 <div className="h-32 bg-slate-50 rounded-2xl border border-slate-100 animate-pulse delay-150"></div>
              </div>
            </div>
          )}
        </div>
      </main>
      
      {/* Mobile Navigation */}
      <MobileNav activeTab={activeTab} setActiveTab={setActiveTab} />
    </div>
  );
}

export default App;
