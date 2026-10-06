import React from 'react';
import { Home, Factory, ChevronRight } from 'lucide-react';
import { motion } from 'framer-motion';

const StockDistribution = () => {
  return (
    <section className="mb-8">
      <div className="flex justify-between items-end mb-6">
        <div>
          <h2 className="text-2xl font-bold text-slate-800 tracking-tight">Stock Distribution</h2>
          <p className="text-slate-400 text-sm font-medium">Yard vs. Factory real-time snapshot</p>
        </div>
        <motion.button 
          whileHover={{ x: 3 }}
          className="text-msm-red text-[11px] font-bold uppercase tracking-widest flex items-center gap-1.5 hover:text-msm-red-hover transition-colors bg-white px-3 py-1.5 rounded-full shadow-sm border border-slate-100"
        >
          Detailed View <ChevronRight className="w-3.5 h-3.5" />
        </motion.button>
      </div>
      
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Yard Stock Card */}
        <motion.div 
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.5, delay: 0.3 }}
          className="glass-card p-8 group hover:border-msm-red/20"
        >
          <div className="flex items-center justify-between mb-8">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-red-50 rounded-2xl group-hover:scale-110 transition-transform duration-500">
                <Home className="w-6 h-6 text-msm-red" />
              </div>
              <h3 className="font-bold text-lg text-slate-700 tracking-tight">Main Storage Yard</h3>
            </div>
            <div className="flex flex-col items-end">
               <span className="text-3xl font-bold text-slate-800 tracking-tighter">245.8 <span className="text-sm font-semibold text-slate-400">MT</span></span>
               <span className="text-[10px] font-bold text-emerald-500 bg-emerald-50 px-2 py-0.5 rounded-full mt-1 border border-emerald-100">+2.4% THIS WEEK</span>
            </div>
          </div>
          
          <div className="space-y-6">
            <div>
              <div className="flex justify-between items-center mb-2.5 text-[11px] font-bold text-slate-400 uppercase tracking-widest">
                <span>Capacity Utilization</span>
                <span className="text-slate-700">78%</span>
              </div>
              <div className="w-full h-3 bg-slate-100 rounded-full overflow-hidden p-0.5 border border-slate-50">
                <motion.div 
                  initial={{ width: 0 }}
                  animate={{ width: '78%' }}
                  transition={{ duration: 1.5, ease: [0.22, 1, 0.36, 1] }}
                  className="h-full bg-msm-red rounded-full shadow-[0_0_12px_rgba(204,0,0,0.3)]" 
                />
              </div>
            </div>
            
            <div className="grid grid-cols-2 gap-4 pt-4 border-t border-slate-50">
               <div className="flex flex-col">
                  <span className="text-[10px] font-bold text-slate-400 uppercase">Incoming</span>
                  <span className="text-lg font-bold text-slate-700">12.5 MT</span>
               </div>
               <div className="flex flex-col border-l border-slate-100 pl-4">
                  <span className="text-[10px] font-bold text-slate-400 uppercase">Reserved</span>
                  <span className="text-lg font-bold text-slate-700">45.0 MT</span>
               </div>
            </div>
          </div>
        </motion.div>
        
        {/* Factory Stock Card */}
        <motion.div 
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.5, delay: 0.4 }}
          className="glass-card p-8 group hover:border-slate-300"
        >
          <div className="flex items-center justify-between mb-8">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-slate-50 rounded-2xl group-hover:scale-110 transition-transform duration-500">
                <Factory className="w-6 h-6 text-slate-500" />
              </div>
              <h3 className="font-bold text-lg text-slate-700 tracking-tight">Active Processing Plant</h3>
            </div>
            <div className="flex flex-col items-end">
               <span className="text-3xl font-bold text-slate-800 tracking-tighter">134.6 <span className="text-sm font-semibold text-slate-400">MT</span></span>
               <span className="text-[10px] font-bold text-amber-500 bg-amber-50 px-2 py-0.5 rounded-full mt-1 border border-amber-100">-1.1% THIS WEEK</span>
            </div>
          </div>
          
          <div className="space-y-6">
            <div>
              <div className="flex justify-between items-center mb-2.5 text-[11px] font-bold text-slate-400 uppercase tracking-widest">
                <span>Active Load Level</span>
                <span className="text-slate-700">45%</span>
              </div>
              <div className="w-full h-3 bg-slate-100 rounded-full overflow-hidden p-0.5 border border-slate-50">
                <motion.div 
                  initial={{ width: 0 }}
                  animate={{ width: '45%' }}
                  transition={{ duration: 1.5, ease: [0.22, 1, 0.36, 1] }}
                  className="h-full bg-slate-500 rounded-full shadow-[0_0_12px_rgba(100,116,139,0.2)]" 
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4 pt-4 border-t border-slate-50">
               <div className="flex flex-col">
                  <span className="text-[10px] font-bold text-slate-400 uppercase">Processing</span>
                  <span className="text-lg font-bold text-slate-700">34.2 MT</span>
               </div>
               <div className="flex flex-col border-l border-slate-100 pl-4">
                  <span className="text-[10px] font-bold text-slate-400 uppercase">QC Pending</span>
                  <span className="text-lg font-bold text-slate-700">8.4 MT</span>
               </div>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
};

export default StockDistribution;
