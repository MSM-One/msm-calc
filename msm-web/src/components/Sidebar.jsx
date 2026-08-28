import React from 'react';
import { LayoutDashboard, Box, BookOpen, BarChart3, Users, Settings, LogOut } from 'lucide-react';
import { motion } from 'framer-motion';

const menuItems = [
  { id: 'dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { id: 'inventory', icon: Box, label: 'Inventory' },
  { id: 'sauda', icon: BookOpen, label: 'Sauda Book' },
  { id: 'reports', icon: BarChart3, label: 'Reports' },
  { id: 'users', icon: Users, label: 'Users' },
];

const Sidebar = ({ activeTab, setActiveTab }) => {
  return (
    <aside className="fixed left-6 top-1/2 -translate-y-1/2 hidden lg:flex flex-col items-center py-8 px-4 glass-pill w-20 z-50">
      <div className="mb-12">
        <div className="w-12 h-12 bg-msm-red rounded-full flex items-center justify-center text-white font-bold text-xl shadow-lg shadow-msm-red-glow">
          M
        </div>
      </div>
      
      <div className="flex flex-col gap-8 flex-1">
        {menuItems.map((item) => (
          <button
            key={item.id}
            onClick={() => setActiveTab(item.id)}
            className="group relative flex items-center justify-center"
          >
            <item.icon 
              className={`w-6 h-6 transition-all duration-300 ${
                activeTab === item.id ? 'text-msm-red' : 'text-slate-400 group-hover:text-msm-red'
              }`}
            />
            
            {activeTab === item.id && (
              <motion.div
                layoutId="active-nav"
                className="absolute -left-4 w-1 h-6 bg-msm-red rounded-r-full"
                transition={{ type: 'spring', stiffness: 300, damping: 30 }}
              />
            )}

            {/* Tooltip */}
            <div className="absolute left-14 px-3 py-1 bg-slate-900 text-white text-xs rounded-md opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none whitespace-nowrap shadow-lg">
              {item.label}
              <div className="absolute top-1/2 -left-1 -translate-y-1/2 w-2 h-2 bg-slate-900 rotate-45" />
            </div>
          </button>
        ))}
      </div>
      
      <div className="mt-12 flex flex-col gap-8 pt-8 border-t border-slate-100">
        <button className="group relative text-slate-400 hover:text-msm-red transition-colors">
          <Settings className="w-6 h-6" />
          <div className="absolute left-14 px-3 py-1 bg-slate-900 text-white text-xs rounded-md opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none whitespace-nowrap shadow-lg">
            Settings
            <div className="absolute top-1/2 -left-1 -translate-y-1/2 w-2 h-2 bg-slate-900 rotate-45" />
          </div>
        </button>
        <button className="group relative text-slate-400 hover:text-msm-red transition-colors">
          <LogOut className="w-6 h-6" />
          <div className="absolute left-14 px-3 py-1 bg-slate-900 text-white text-xs rounded-md opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none whitespace-nowrap shadow-lg">
            Logout
            <div className="absolute top-1/2 -left-1 -translate-y-1/2 w-2 h-2 bg-slate-900 rotate-45" />
          </div>
        </button>
      </div>
    </aside>
  );
};

export default Sidebar;
