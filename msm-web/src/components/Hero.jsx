import React from 'react';
import { Search, Bell, RotateCcw, TrendingUp, AlertCircle, Factory } from 'lucide-react';
import { motion } from 'framer-motion';

const Hero = () => {
  return (
    <section className="relative overflow-hidden glass-card bg-msm-red text-white p-8 mb-8 border-none ring-1 ring-white/10">
      {/* Background patterns */}
      <div className="absolute top-0 right-0 w-64 h-64 bg-white/10 rounded-full -mr-20 -mt-20 blur-3xl animate-pulse" />
      <div className="absolute bottom-0 left-0 w-48 h-48 bg-white/5 rounded-full -ml-10 -mb-10 blur-2xl" />
      
      <div className="relative z-10 flex flex-col md:flex-row justify-between items-start md:items-center">
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
        >
          <div className="inline-flex items-center gap-2 px-3 py-1 bg-white/10 rounded-full text-[10px] uppercase tracking-wider font-semibold backdrop-blur-sm border border-white/10 mb-6">
            <div className="w-1.5 h-1.5 bg-green-400 rounded-full animate-pulse shadow-[0_0_8px_rgba(74,222,128,0.6)]" />
            Live Inventory Sync
          </div>
          
          <h1 className="text-3xl md:text-5xl font-bold mb-3 tracking-tight">Welcome back, <span className="text-white/90">Jordan</span> 👋</h1>
          <p className="text-white/70 max-w-md font-light text-lg">
            Monitor your yards and factory operations in real-time.
          </p>
          
          <div className="flex flex-wrap gap-4 mt-10">
            {[
              { icon: TrendingUp, label: 'vs. yesterday', value: '-6.2%', color: 'text-white' },
              { icon: AlertCircle, label: 'need attention', value: '3 items', color: 'text-rose-200' },
              { icon: Factory, label: 'factory usage', value: '+12% avg', color: 'text-white' }
            ].map((stat, i) => (
              <motion.div 
                key={i}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: 0.2 + i * 0.1 }}
                className="glass-card bg-white/10 border-white/5 p-4 min-w-[150px] hover:bg-white/15 transition-colors cursor-default"
              >
                <div className="flex items-center gap-2 text-white/50 text-[11px] font-medium uppercase tracking-wide mb-1">
                  <stat.icon className="w-3 h-3" />
                  {stat.label}
                </div>
                <div className={`text-xl font-bold ${stat.color}`}>{stat.value}</div>
              </motion.div>
            ))}
          </div>
        </motion.div>
        
        <div className="hidden md:flex gap-4 mt-6 md:mt-0">
          <button className="w-11 h-11 glass-card bg-white/10 border-white/10 flex items-center justify-center hover:bg-white/20 transition-all active:scale-95 group">
            <RotateCcw className="w-5 h-5 group-hover:rotate-180 transition-transform duration-500" />
          </button>
          <button className="w-11 h-11 glass-card bg-white/10 border-white/10 flex items-center justify-center relative hover:bg-white/20 transition-all active:scale-95">
            <Bell className="w-5 h-5 transition-transform hover:shake" />
            <div className="absolute top-3 right-3 w-2.5 h-2.5 bg-rose-500 rounded-full border-2 border-msm-red" />
          </button>
          <div className="w-11 h-11 glass-card bg-white border-white flex items-center justify-center text-msm-red font-bold text-lg shadow-xl shadow-msm-red/20">
            J
          </div>
        </div>
      </div>
    </section>
  );
};

export default Hero;
