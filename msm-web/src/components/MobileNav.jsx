import React from 'react';
import { LayoutDashboard, Box, BookOpen, BarChart3, Users } from 'lucide-react';
import { motion } from 'framer-motion';

const MobileNav = ({ activeTab, setActiveTab }) => {
  const items = [
    { id: 'dashboard', icon: LayoutDashboard, label: 'Dash' },
    { id: 'inventory', icon: Box, label: 'Inv' },
    { id: 'sauda', icon: BookOpen, label: 'Book' },
    { id: 'reports', icon: BarChart3, label: 'Rep' },
    { id: 'users', icon: Users, label: 'User' },
  ];

  return (
    <nav className="fixed bottom-4 left-4 right-4 lg:hidden glass-pill h-16 flex items-center justify-around px-2 z-50 shadow-[0_8px_30px_rgb(0,0,0,0.12)] border-white/30">
      {items.map((item) => (
        <button
          key={item.id}
          onClick={() => setActiveTab(item.id)}
          className="relative group p-2 rounded-2xl flex flex-col items-center justify-center transition-all duration-300"
        >
          {activeTab === item.id && (
            <motion.div 
              layoutId="mobile-nav-active"
              className="absolute inset-0 bg-msm-red rounded-2xl -z-10 shadow-lg shadow-msm-red/20"
              transition={{ type: 'spring', stiffness: 400, damping: 30 }}
            />
          )}
          <item.icon className={`w-5 h-5 transition-colors duration-300 ${
            activeTab === item.id ? 'text-white' : 'text-slate-400'
          }`} />
          <span className={`text-[9px] font-bold mt-1 uppercase tracking-tighter ${
            activeTab === item.id ? 'text-white' : 'text-slate-400'
          }`}>{item.label}</span>
        </button>
      ))}
    </nav>
  );
};

export default MobileNav;
