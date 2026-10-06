import React from 'react';
import { Package, ArrowRightLeft, MoveRight, AlertTriangle, TrendingUp, TrendingDown } from 'lucide-react';
import { motion } from 'framer-motion';

const kpis = [
  {
    title: 'Total Stock',
    value: '380.4 MT',
    trend: '+4.8%',
    trendUp: true,
    icon: Package,
    color: 'bg-msm-red',
    light: false,
  },
  {
    title: "Today's Activity",
    value: '0 Txns',
    trend: '-2.1%',
    trendUp: false,
    icon: ArrowRightLeft,
    color: 'bg-white',
    iconColor: 'text-msm-red',
    light: true,
  },
  {
    title: 'Stock Out Today',
    value: '0.00 MT',
    trend: '+6.2%',
    trendUp: true,
    icon: MoveRight,
    color: 'bg-white',
    iconColor: 'text-msm-red',
    light: true,
  },
];

const KPICard = ({ kpi, index, onNavigate }) => {
  const Icon = kpi.icon;
  
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.1, duration: 0.4 }}
      whileHover={{ y: -5, boxShadow: '0 20px 40px -15px rgba(0,0,0,0.07)' }}
      onClick={() => onNavigate && onNavigate('reports')}
      className={`glass-card p-6 flex flex-col justify-between min-h-[160px] relative overflow-hidden group cursor-pointer ${
        !kpi.light ? 'border-transparent ring-1 ring-black/5' : ''
      }`}
    >
      <div className="flex justify-between items-start mb-6">
        <div>
          <p className="text-slate-400 text-[11px] font-bold uppercase tracking-wider mb-1">{kpi.title}</p>
          <h3 className="text-3xl font-bold text-slate-800 tracking-tight">{kpi.value}</h3>
        </div>
        
        <div className={`flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-bold ${
          kpi.trendUp ? 'bg-emerald-50 text-emerald-600 border border-emerald-100' : 'bg-rose-50 text-rose-600 border border-rose-100'
        }`}>
          {kpi.trendUp ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
          {kpi.trend}
        </div>
      </div>
      
      <div className="flex justify-end items-end">
        <div className={`p-4 rounded-2xl ${kpi.color} ${kpi.iconColor || 'text-white'} shadow-2xl transition-transform group-hover:scale-110 duration-500`}>
          <Icon className="w-6 h-6" />
        </div>
      </div>
      
      {/* Subtle background decoration */}
      <div className={`absolute -right-4 -bottom-4 w-24 h-24 rounded-full opacity-[0.03] group-hover:opacity-[0.05] transition-opacity ${
        !kpi.light ? 'bg-white' : 'bg-msm-red'
      }`} />
    </motion.div>
  );
};

const KPICards = ({ onNavigate }) => {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
      {kpis.map((kpi, i) => (
        <KPICard key={i} kpi={kpi} index={i} onNavigate={onNavigate} />
      ))}
    </div>
  );
};

export default KPICards;
